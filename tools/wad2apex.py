#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Rafael Colatusso
# mus2mid() adapta mus2mid.c do Chocolate Doom (GPL-2.0-or-later).
# Copyright (c) 1993-1996 id Software, Inc.; 2005-2014 Simon Howard;
# 2006 Ben Ryves. Consulte NOTICE para a fonte e a atribuição completa.
"""
wad2apex — carrega o DOOM1.WAD oficial e gera WadData.cls (Apex puro).

Apex nao tem file I/O nem Blob/EncodingUtil. Entao este gerador faz o papel do
"carregador" (como um Static Resource numa org): le o WAD oficial, extrai os
dados REAIS do mapa pedido, remonta um PWAD valido (header + lumps + directory)
e embute em base64 chunkado. O parser de WAD roda do lado do Apex.

Geometria real:
  VERTEXES, LINEDEFS, SIDEDEFS, SECTORS, THINGS
Derivados (compostos aqui, lidos como lump no Apex):
  PAL0    -> paleta 0 do PLAYPAL (256 x RGB)
  TEXMETA -> K texturas de parede: w(u16), h(u16), off(u32) dentro de TEXPIX
  TEXPIX  -> pixels (palette-indexed, col-major) de todas as texturas usadas
  SECT    -> por setor: floorH, ceilH, luz, idx flat chao/teto, flag de ceu
  LINE    -> por linedef: setor front/back + texturas up/mid/lo de cada lado
  FLATPIX -> flats 64x64 de chao/teto (palette-indexed)
  HDR     -> startFloorH (altura do olho), skyTexIdx
  GUN*/MON*/HUD/SINE -> arma, monstros, hud e LUT de seno

O render do Apex e um PORTAL WALKER: por coluna, atravessa os linedefs em ordem
de distancia, desenha degraus (upper/lower) e chao/teto por setor (altura real),
ate bater numa parede solida. E o que da a cara das salas do E1M1.

Uso: python tools/wad2apex.py doom1.wad E1M1 --out WadData.cls
"""
import struct, sys, base64, math, argparse, hashlib

GEO = ["THINGS", "LINEDEFS", "SIDEDEFS", "VERTEXES", "SECTORS"]
CHUNK = 8000
NOTEX = 0xFFFF        # sentinela: lado sem textura ("-")


# ---------- leitura do WAD ----------
def read_dir(d):
    magic, n, off = struct.unpack("<4sii", d[:12])
    entries = [struct.unpack("<ii8s", d[off + i * 16: off + i * 16 + 16]) for i in range(n)]
    return [(fp, sz, nm.rstrip(b"\0").decode("latin1")) for fp, sz, nm in entries]


class Wad:
    def __init__(self, path):
        self.d = open(path, "rb").read()
        self.md5 = hashlib.md5(self.d).hexdigest()
        self.dirs = read_dir(self.d)
        self.names = [e[2] for e in self.dirs]

    def idx(self, nm, start=0):
        return self.names.index(nm, start)

    def lump(self, nm, start=0):
        fp, sz, _ = self.dirs[self.idx(nm, start)]
        return self.d[fp:fp + sz]

    def load_picture(self, name):
        """le um lump no formato 'picture' do DOOM (sprites/patches).
        retorna (w, h, leftoff, topoff, pixels col-major) com 255 = transparente."""
        pd = self.lump(name)
        w, h, lo, to = struct.unpack("<hhhh", pd[:8])
        colofs = [struct.unpack("<i", pd[8 + i * 4:12 + i * 4])[0] for i in range(w)]
        cols = [bytearray([255]) * h for _ in range(w)]   # 255 = transparente
        for x in range(w):
            p = colofs[x]
            while pd[p] != 0xFF:
                top, ln = pd[p], pd[p + 1]
                p += 3
                for k in range(ln):
                    y = top + k
                    if 0 <= y < h:
                        v = pd[p + k]
                        cols[x][y] = 254 if v == 255 else v   # libera 255 p/ transparencia
                p += ln + 1
        flat = bytearray()
        for x in range(w):
            flat += cols[x]
        return w, h, lo, to, bytes(flat)


# ---------- texturas (PNAMES + TEXTURE1 + patches) ----------
class Textures:
    def __init__(self, wad):
        self.wad = wad
        pn = wad.lump("PNAMES")
        cnt = struct.unpack("<i", pn[:4])[0]
        self.pnames = [pn[4 + i * 8:12 + i * 8].rstrip(b"\0").decode("latin1").upper() for i in range(cnt)]
        self.defs = {}
        for tl in ("TEXTURE1", "TEXTURE2"):
            if tl not in wad.names:
                continue
            t1 = wad.lump(tl)
            ntex = struct.unpack("<i", t1[:4])[0]
            offs = [struct.unpack("<i", t1[4 + i * 4:8 + i * 4])[0] for i in range(ntex)]
            for o in offs:
                name = t1[o:o + 8].rstrip(b"\0").decode("latin1").upper()
                w, h = struct.unpack("<hh", t1[o + 12:o + 16])
                npatch = struct.unpack("<h", t1[o + 20:o + 22])[0]
                patches = [struct.unpack("<hhh", t1[o + 22 + p * 10:o + 28 + p * 10]) for p in range(npatch)]
                self.defs[name] = (w, h, patches)
        self._patch_cache = {}

    def _patch(self, pidx):
        if pidx in self._patch_cache:
            return self._patch_cache[pidx]
        pd = self.wad.lump(self.pnames[pidx])
        w, h = struct.unpack("<hh", pd[:4])
        colofs = [struct.unpack("<i", pd[8 + i * 4:12 + i * 4])[0] for i in range(w)]
        cols = [bytearray(h) for _ in range(w)]
        mask = [bytearray(h) for _ in range(w)]
        for x in range(w):
            p = colofs[x]
            while pd[p] != 0xFF:
                top, ln = pd[p], pd[p + 1]
                p += 3
                for k in range(ln):
                    y = top + k
                    if 0 <= y < h:
                        cols[x][y] = pd[p + k]; mask[x][y] = 1
                p += ln + 1
        self._patch_cache[pidx] = (w, h, cols, mask)
        return self._patch_cache[pidx]

    def compose(self, name):
        """retorna (w, h, bytes col-major) da textura ja montada."""
        w, h, patches = self.defs[name]
        pix = [bytearray(h) for _ in range(w)]   # col-major, 0 = vazio
        for ox, oy, pidx in patches:
            pw, ph, cols, mask = self._patch(pidx)
            for x in range(pw):
                tx = ox + x
                if not (0 <= tx < w):
                    continue
                for y in range(ph):
                    ty = oy + y
                    if 0 <= ty < h and mask[x][y]:
                        pix[tx][ty] = cols[x][y]
        flat = bytearray()
        for x in range(w):
            flat += pix[x]
        return w, h, bytes(flat)


def s16(v):
    return v - 0x10000 if v >= 0x8000 else v


def load_sfx(wad, name):
    """decodifica um lump DS* (formato DMX/DSP) -> (rate, pcm 8-bit unsigned).
    header: u16 fmt(=3), u16 rate, u32 nsamples; depois 16 bytes de guarda,
    PCM 8-bit unsigned, e mais 16 de guarda no fim (removidos)."""
    d = wad.lump(name)
    fmt, rate, nsamp = struct.unpack("<HHI", d[:8])
    body = d[8:8 + nsamp] if 8 + nsamp <= len(d) else d[8:]
    pcm = body[16:-16] if len(body) > 32 else body
    return rate, pcm


def mus2mid(mus):
    """converte um lump MUS (formato DMX) -> bytes MIDI type-0.
    porta do mus2mid.c (Chocolate Doom). MUS roda a 140Hz -> MIDI div=70 @120bpm."""
    if mus[:4] != b"MUS\x1a":
        return None
    score_len, score_start = struct.unpack("<HH", mus[4:8])
    # MUS controller -> MIDI controller (indice 0 = program change, tratado a parte)
    cmap = [0, 0x00, 0x01, 0x07, 0x0A, 0x0B, 0x5B, 0x5D, 0x40, 0x43, 0x78, 0x7B, 0x7E, 0x7F, 0x79]
    PERC = 9                                  # canal de percussao no MIDI (15 no MUS)
    track = bytearray()
    chan_vel = [127] * 16
    chan_map = [-1] * 16
    alloc = [0]

    def midi_ch(mc):
        if mc == 15:
            return PERC
        if chan_map[mc] < 0:
            chan_map[mc] = alloc[0]; alloc[0] += 1
            if alloc[0] == PERC:
                alloc[0] += 1
        return chan_map[mc]

    def vlq(value):
        out = bytearray()
        buf = value & 0x7F
        value >>= 7
        while value:
            buf = (buf << 8) | 0x80 | (value & 0x7F)
            value >>= 7
        while True:
            out.append(buf & 0xFF)
            if buf & 0x80:
                buf >>= 8
            else:
                break
        return out

    queued = [0]

    def ev(status, *data):
        track.extend(vlq(queued[0])); queued[0] = 0
        track.append(status)
        for dd in data:
            track.append(dd & 0xFF)

    pos = score_start
    end = min(len(mus), score_start + score_len)
    done = False
    while pos < end and not done:
        desc = mus[pos]; pos += 1
        etype = (desc >> 4) & 7
        mc = midi_ch(desc & 0xF)
        if etype == 0:                        # release note
            ev(0x80 | mc, mus[pos] & 0x7F, 0); pos += 1
        elif etype == 1:                      # play note
            note = mus[pos]; pos += 1
            if note & 0x80:
                note &= 0x7F
                chan_vel[desc & 0xF] = mus[pos] & 0x7F; pos += 1
            ev(0x90 | mc, note & 0x7F, chan_vel[desc & 0xF])
        elif etype == 2:                      # pitch bend (1 byte MUS -> 14-bit MIDI)
            val = mus[pos] * 64; pos += 1
            ev(0xE0 | mc, val & 0x7F, (val >> 7) & 0x7F)
        elif etype == 3:                      # system event (controller sem valor)
            c = mus[pos]; pos += 1
            ev(0xB0 | mc, cmap[c] if c < len(cmap) else 0, 0)
        elif etype == 4:                      # change controller
            c = mus[pos]; pos += 1
            v = mus[pos]; pos += 1
            if c == 0:
                ev(0xC0 | mc, v & 0x7F)       # program change
            else:
                ev(0xB0 | mc, cmap[c] if c < len(cmap) else 0, v & 0x7F)
        elif etype == 6:                      # score end
            done = True
        # etype 5 (fim de compasso) e 7 (nao usado): sem dados
        if desc & 0x80:                       # delay (VLQ base-128)
            delay = 0
            while True:
                b = mus[pos]; pos += 1
                delay = delay * 128 + (b & 0x7F)
                if not (b & 0x80):
                    break
            queued[0] += delay
    track.extend(b"\x00\xFF\x2F\x00")         # end of track
    midi = bytearray(b"MThd\x00\x00\x00\x06\x00\x00\x00\x01\x00\x46")  # fmt0, 1 trk, div=70
    midi += b"MTrk" + struct.pack(">I", len(track)) + track
    return bytes(midi)


# ---------- BSP: acha o setor que contem um ponto (pro olho do player) ----------
def point_sector(wad, mapi, px, py):
    nodes = wad.lump("NODES", mapi)
    ssec = wad.lump("SSECTORS", mapi)
    segs = wad.lump("SEGS", mapi)
    ld = wad.lump("LINEDEFS", mapi)
    sd = wad.lump("SIDEDEFS", mapi)
    if not nodes:
        return 0
    node = len(nodes) // 28 - 1
    while not (node & 0x8000):
        o = node * 28
        nx, ny, ndx, ndy = struct.unpack("<hhhh", nodes[o:o + 8])
        rchild, lchild = struct.unpack("<HH", nodes[o + 24:o + 28])
        left = ndy * (px - nx)
        right = (py - ny) * ndx
        node = rchild if right < left else lchild
    sub = node & 0x7FFF
    segcnt, firstseg = struct.unpack("<HH", ssec[sub * 4:sub * 4 + 4])
    so = firstseg * 12
    sv1, sv2, sang, sline, sside, soff = struct.unpack("<HHhHHh", segs[so:so + 12])
    front_sd, back_sd = struct.unpack("<HH", ld[sline * 14 + 10:sline * 14 + 14])
    sidedef = front_sd if sside == 0 else back_sd
    return struct.unpack("<H", sd[sidedef * 30 + 28:sidedef * 30 + 30])[0]


def build(wad, mapname):
    i = wad.idx(mapname)
    tex = Textures(wad)
    sdraw = wad.lump("SIDEDEFS", i)
    ld = wad.lump("LINEDEFS", i)
    secd = wad.lump("SECTORS", i)

    # ---- tabela unica de texturas de PAREDE (todos os lados: up/mid/lo) ----
    tex_index = {}        # nome -> indice
    tex_order = []        # nomes na ordem dos indices

    def tex_idx(name):
        name = name.rstrip("\0").upper()
        if name in ("", "-") or name not in tex.defs:
            return NOTEX
        if name not in tex_index:
            tex_index[name] = len(tex_order); tex_order.append(name)
        return tex_index[name]

    # ceu do E1M1 (textura SKY1) -> indice fixo na tabela de parede
    sky_tex_idx = tex_idx("SKY1")

    def side(sidx):
        """(xoff, yoff, upperIdx, lowerIdx, midIdx, sector) de um sidedef."""
        o = sidx * 30
        xoff, yoff = struct.unpack("<hh", sdraw[o:o + 4])
        up = sdraw[o + 4:o + 12].rstrip(b"\0").decode("latin1")
        lo = sdraw[o + 12:o + 20].rstrip(b"\0").decode("latin1")
        mi = sdraw[o + 20:o + 28].rstrip(b"\0").decode("latin1")
        sector = struct.unpack("<H", sdraw[o + 28:o + 30])[0]
        return xoff, yoff, tex_idx(up), tex_idx(lo), tex_idx(mi), sector

    # ---- flats de chao/teto (64x64), tabela unica ----
    flat_index = {}
    flat_order = []

    def flat_idx(name):
        name = name.rstrip("\0").upper()
        if name not in flat_index:
            flat_index[name] = len(flat_order); flat_order.append(name)
        return flat_index[name]

    # ---- vizinhanca de setores (menor teto vizinho -> alvo de porta aberta) ----
    nsect = len(secd) // 26
    def sec_ceil(s):
        return struct.unpack("<h", secd[s * 26 + 2:s * 26 + 4])[0]
    neigh = [[] for _ in range(nsect)]
    nline = len(ld) // 14
    for k in range(nline):
        o = k * 14
        fsd, bsd = struct.unpack("<HH", ld[o + 10:o + 14])
        if bsd == 0xFFFF:
            continue
        fsec = struct.unpack("<H", sdraw[fsd * 30 + 28:fsd * 30 + 30])[0]
        bsec = struct.unpack("<H", sdraw[bsd * 30 + 28:bsd * 30 + 30])[0]
        if fsec != bsec:
            neigh[fsec].append(sec_ceil(bsec)); neigh[bsec].append(sec_ceil(fsec))

    # ---- SECT: por setor (na ordem do WAD) ----
    sect = bytearray(struct.pack("<H", nsect))
    for s in range(nsect):
        o = s * 26
        fh, ch = struct.unpack("<hh", secd[o:o + 4])
        floorpic = secd[o + 4:o + 12].rstrip(b"\0").decode("latin1").upper()
        ceilpic = secd[o + 12:o + 20].rstrip(b"\0").decode("latin1").upper()
        light = struct.unpack("<h", secd[o + 20:o + 22])[0]
        light = max(0, min(255, light))
        fidx = flat_idx(floorpic)
        cidx = flat_idx(ceilpic)
        sky = 1 if ceilpic == "F_SKY1" else 0
        open_ceil = (min(neigh[s]) - 4) if neigh[s] else ch        # teto de porta aberta
        sect += struct.pack("<hhBHHBh", fh, ch, light, fidx, cidx, sky, open_ceil)  # 12 bytes

    # ---- LINE: por linedef (na ordem do WAD, casa com Wad.cls) ----
    # portas manuais do DOOM (push to open): DR/D1, normais e rapidas/com chave
    DOORS = {1, 26, 27, 28, 31, 32, 33, 34, 117, 118}
    line = bytearray()
    for k in range(nline):
        o = k * 14
        front_sd, back_sd = struct.unpack("<HH", ld[o + 10:o + 14])
        special = struct.unpack("<H", ld[o + 6:o + 8])[0]
        door = 1 if special in DOORS else 0
        fX, fY, fUp, fLo, fMid, fSec = side(front_sd)
        if back_sd != 0xFFFF:
            bX, bY, bUp, bLo, bMid, bSec = side(back_sd)
        else:
            bX, bUp, bLo, bMid, bSec = 0, NOTEX, NOTEX, NOTEX, -1
        line += struct.pack("<hhHHHHHHhhH", fSec, bSec, fUp, fMid, fLo,
                            bUp, bMid, bLo, fX, bX, door)               # 22 bytes/linha

    # ---- LACT/STAG: specials de gameplay (lift/floor/exit) + tag e floor vizinho ----
    # action: 0 nada, 1 lift, 2 floor-lower, 3 exit | trig: 0 walk (cruzar), 1 switch (USE).
    # a classificacao special->acao e DADO (decidida aqui); o engine fica generico.
    LIFT = {88, 62, 10, 21, 121, 122, 123, 120, 87, 5}
    FLOORLOWER = {36, 23, 19, 38, 70, 60, 82, 84, 102}
    EXIT = {11, 51, 52, 124}

    def classify(sp):
        if sp in EXIT:
            return 3, 1                      # exit = alavanca (USE)
        if sp in LIFT:
            return 1, 0                      # lift = walk (no E1M1 o 88 e WR)
        if sp in FLOORLOWER:
            return 2, 0                      # floor lower = walk
        return 0, 0

    # portas trancadas: special -> cor de chave (1 azul, 2 amarelo, 3 vermelho; 0 = livre)
    KEY_DOORS = {26: 1, 32: 1, 27: 2, 34: 2, 28: 3, 33: 3}
    lact = bytearray()
    lkey = bytearray()
    for k in range(nline):
        o = k * 14
        special = struct.unpack("<H", ld[o + 6:o + 8])[0]
        tag = struct.unpack("<H", ld[o + 8:o + 10])[0]
        action, trig = classify(special)
        lact += struct.pack("<BBH", action, trig, tag)
        lkey.append(KEY_DOORS.get(special, 0))

    def sec_floor(s):
        return struct.unpack("<h", secd[s * 26:s * 26 + 2])[0]

    neighF = [[] for _ in range(nsect)]
    for k in range(nline):
        o = k * 14
        fsd, bsd = struct.unpack("<HH", ld[o + 10:o + 14])
        if bsd == 0xFFFF:
            continue
        fsec = struct.unpack("<H", sdraw[fsd * 30 + 28:fsd * 30 + 30])[0]
        bsec = struct.unpack("<H", sdraw[bsd * 30 + 28:bsd * 30 + 30])[0]
        if fsec != bsec:
            neighF[fsec].append(sec_floor(bsec)); neighF[bsec].append(sec_floor(fsec))
    stag = bytearray()
    for s in range(nsect):
        tag = struct.unpack("<H", secd[s * 26 + 24:s * 26 + 26])[0]    # tag do setor (offset 24)
        low = min(neighF[s]) if neighF[s] else sec_floor(s)
        stag += struct.pack("<Hh", tag, low)                           # tag + menor floor vizinho

    # ---- compoe TEXPIX + TEXMETA (todas as texturas de parede usadas) ----
    texpix = bytearray()
    texmeta = bytearray(struct.pack("<H", len(tex_order)))
    for nm in tex_order:
        w, h, flat = tex.compose(nm)
        texmeta += struct.pack("<HHI", w, h, len(texpix))
        texpix += flat

    # ---- FLATPIX: concatena os flats 64x64 (palette-indexed) ----
    flatpix = bytearray()
    for nm in flat_order:
        try:
            data = wad.lump(nm)
        except ValueError:
            data = b"\0" * 4096
        data = (data + b"\0" * 4096)[:4096]
        flatpix += data

    # ---- SECGRID: setor por celula do grid (BSP) -> olho dinamico + colisao de altura ----
    nodes = wad.lump("NODES", i); ssec = wad.lump("SSECTORS", i); segs = wad.lump("SEGS", i)
    def node_sector(px, py):
        if not nodes:
            return 0
        node = len(nodes) // 28 - 1
        while not (node & 0x8000):
            no = node * 28
            nx, ny, ndx, ndy = struct.unpack("<hhhh", nodes[no:no + 8])
            rc, lc = struct.unpack("<HH", nodes[no + 24:no + 28])
            node = rc if ((py - ny) * ndx) < (ndy * (px - nx)) else lc
        sub = node & 0x7FFF
        scnt, fseg = struct.unpack("<HH", ssec[sub * 4:sub * 4 + 4])
        sv1, sv2, sang, sline, sside, soff = struct.unpack("<HHhHHh", segs[fseg * 12:fseg * 12 + 12])
        fsd2, bsd2 = struct.unpack("<HH", ld[sline * 14 + 10:sline * 14 + 14])
        sid = fsd2 if sside == 0 else bsd2
        return struct.unpack("<H", sdraw[sid * 30 + 28:sid * 30 + 30])[0]
    vtx = wad.lump("VERTEXES", i); nv = len(vtx) // 4
    xs = [struct.unpack("<h", vtx[v * 4:v * 4 + 2])[0] for v in range(nv)]
    ys = [struct.unpack("<h", vtx[v * 4 + 2:v * 4 + 4])[0] for v in range(nv)]
    minX, maxX = min(xs), max(xs); minY, maxY = min(ys), max(ys)
    CU = 16
    gw = (maxX - minX) // CU + 2; gh = (maxY - minY) // CU + 2
    secgrid = bytearray(struct.pack("<HH", gw, gh))
    for cy in range(gh):
        for cx in range(gw):
            s = node_sector(minX + cx * CU + CU // 2, minY + cy * CU + CU // 2)
            secgrid.append(min(254, s))

    # ---- HDR: altura do olho (setor do start) + indice da textura de ceu ----
    th = wad.lump("THINGS", i)
    psx = psy = 0
    for k in range(len(th) // 10):
        x, y, ang, typ, fl = struct.unpack("<hhhhh", th[k * 10:k * 10 + 10])
        if typ == 1:
            psx, psy = x, y
            break
    start_sec = node_sector(psx, psy)
    start_floor = struct.unpack("<h", secd[start_sec * 26:start_sec * 26 + 2])[0]
    hdr = struct.pack("<hHHH", start_floor, sky_tex_idx, nsect, nline)

    # ---- armas: sprites (idle/fire/flash por arma) + tabela data-driven ----
    def sprite_lump(name):
        w, h, lo, to, flat = wad.load_picture(name)
        return struct.pack("<HHhh", w, h, lo, to) + flat
    # arma -> (idle, fire, flash, ammoType, dmg, cone, cooldown, perShot, flashTh, sfxName)
    # ammoType: 0 balas, 1 cartuchos, 2 foguetes, 3 celulas
    WEAPONS = {
        2: ("PISGA0", "PISGB0", "PISFA0", 0, 16, 26, 9, 1, 5, "DSPISTOL"),
        3: ("SHTGA0", "SHTGD0", "SHTFA0", 1, 50, 64, 24, 1, 20, "DSSHOTGN"),
        4: ("CHGGA0", "CHGGB0", "CHGFA0", 0, 16, 24, 4, 1, 3, "DSPISTOL"),
        5: ("MISGA0", "MISGB0", "MISFA0", 2, 90, 40, 28, 1, 6, "DSRLAUNC"),
        6: ("PLSGA0", "PLSGB0", "PLSFA0", 3, 22, 24, 5, 1, 3, "DSPLASMA"),
        7: ("BFGGA0", "BFGGB0", "BFGFA0", 3, 200, 90, 50, 40, 20, "DSBFG"),
    }

    def wsprite(nm, fallback):
        return sprite_lump(nm) if nm in wad.names else sprite_lump(fallback)

    weapon_lumps = []
    for wn in range(2, 8):
        idle, fire, flash = WEAPONS[wn][0], WEAPONS[wn][1], WEAPONS[wn][2]
        weapon_lumps.append(("WP" + str(wn) + "I", wsprite(idle, "PISGA0")))
        weapon_lumps.append(("WP" + str(wn) + "F", wsprite(fire, "PISGB0")))
        weapon_lumps.append(("WP" + str(wn) + "L", wsprite(flash, "PISFA0")))
    fireball = sprite_lump("BAL1A0") if "BAL1A0" in wad.names else b""   # bola de fogo do imp

    # ---- monstros: spawns (THINGS) + sprites (vivo de frente + corpo) ----
    MON = {3004: 0, 9: 1, 3001: 2}    # zombieman, shotgun guy, imp -> classe 0/1/2
    BASE = ["POSS", "SPOS", "TROO"]   # prefixo do sprite por classe
    ATK = ["POSSF1", "SPOSF1", "TROOG1"]      # pose de ataque (frontal: disparo/arremesso)
    DEATH = [["POSSH0", "POSSI0", "POSSJ0", "POSSK0", "POSSL0"],
             ["SPOSH0", "SPOSI0", "SPOSJ0", "SPOSK0", "SPOSL0"],
             ["TROOI0", "TROOJ0", "TROOK0", "TROOL0", "TROOM0"]]
    # rotacao 0..7 -> (indice fisico, espelhar): 5 sprites cobrem as 8 vistas (3 espelhados)
    MROT = [(0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (3, 1), (2, 1), (1, 1)]

    def rot_phys(base, frame):
        """5 sprites fisicos de um frame (rot 1,2,3,4,5); rot1 como fallback se faltar."""
        suff = [frame + "1", frame + "2" + frame + "8", frame + "3" + frame + "7",
                frame + "4" + frame + "6", frame + "5"]
        first = sprite_lump(base + suff[0])
        return [sprite_lump(base + s) if (base + s) in wad.names else first for s in suff]

    # drop ao morrer (igual DOOM): zombieman -> clip (5 balas), shotgun guy -> shotgun; imp nada.
    # (cat, amt) na convencao do ITEM_FX; 255 = sem drop.
    DROPS = {0: (0, 5), 1: (6, 3), 2: (255, 0)}
    ents = bytearray()
    nent = 0
    for k in range(len(th) // 10):
        x, y, ang, typ, fl = struct.unpack("<hhhhh", th[k * 10:k * 10 + 10])
        if typ in MON:
            dc, da = DROPS[MON[typ]]
            ents += struct.pack("<hhHBB", x, y, MON[typ], dc, da)   # 8 bytes/monstro
            nent += 1
    ents = struct.pack("<H", nent) + ents
    mon_lumps = []
    for c in range(3):
        for p, spr in enumerate(rot_phys(BASE[c], "A")):
            mon_lumps.append(("MIA" + str(c) + str(p), spr))    # idle (frame A), rot fisica p
        for p, spr in enumerate(rot_phys(BASE[c], "B")):
            mon_lumps.append(("MIB" + str(c) + str(p), spr))    # walk (frame B), rot fisica p
        mon_lumps.append(("MONK" + str(c), sprite_lump(ATK[c])))
        for f in range(5):
            mon_lumps.append(("MOND" + str(c) + str(f), sprite_lump(DEATH[c][f])))
    mrot = bytearray()
    for ph, mi in MROT:
        mrot.append(ph); mrot.append(mi)

    # ---- itens (pickups): spawns (THINGS nao-monstro) + sprites + efeito por tipo ----
    # cat: 0 balas, 1 cartuchos, 2 vida(cap100), 3 vida(cap200), 4 armadura-set, 5 armadura+(cap200),
    #      6 arma (amount=numero da arma), 7 chave (amount=id)
    ITEM_FX = {
        2018: (4, 100, "ARM1A0"), 2019: (4, 200, "ARM2A0"),
        2015: (5, 1, "BON2A0"), 2014: (3, 1, "BON1A0"),
        2011: (2, 10, "STIMA0"), 2012: (2, 25, "MEDIA0"), 2013: (3, 100, "SOULA0"),
        2007: (0, 10, "CLIPA0"), 2048: (0, 50, "AMMOA0"),
        2008: (1, 4, "SHELA0"), 2049: (1, 20, "SBOXA0"),
        2010: (8, 1, "ROCKA0"), 2046: (8, 5, "BROKA0"),
        2047: (9, 20, "CELLA0"), 2017: (9, 100, "CELPA0"),
        2001: (6, 3, "SHOTA0"), 2002: (6, 4, "MGUNA0"),
        2003: (6, 5, "LAUNA0"), 2004: (6, 6, "PLASA0"), 2006: (6, 7, "BFUGA0"),
        5: (7, 1, "BKEYA0"), 6: (7, 2, "YKEYA0"), 13: (7, 3, "RKEYA0"),
        40: (7, 4, "BSKUA0"), 39: (7, 5, "YSKUA0"), 38: (7, 6, "RSKUA0"),
    }
    item_sprites = []
    item_spr_idx = {}
    items = bytearray()
    nitems = 0
    for k in range(len(th) // 10):
        x, y, ang, typ, fl = struct.unpack("<hhhhh", th[k * 10:k * 10 + 10])
        if typ in ITEM_FX:
            cat, amt, spr = ITEM_FX[typ]
            if spr not in wad.names:
                continue                       # sprite ausente nesse WAD -> ignora o item
            if spr not in item_spr_idx:
                item_spr_idx[spr] = len(item_sprites); item_sprites.append(spr)
            items += struct.pack("<hhHBh", x, y, item_spr_idx[spr], cat, amt)   # 9 bytes
            nitems += 1
    items = struct.pack("<H", nitems) + items
    item_spr_lumps = [("ISPR" + str(j), sprite_lump(spr)) for j, spr in enumerate(item_sprites)]

    # ---- HUD: barra STBAR real + digitos vermelhos + % + rosto por nivel de vida ----
    hud_lumps = []
    hud_lumps.append(("STBAR", sprite_lump("STBAR")))            # barra de status icônica
    hud_lumps.append(("STARMS", sprite_lump("STARMS")))          # painel "ARMS" (single-player)
    for nd in range(10):
        hud_lumps.append(("NUM" + str(nd), sprite_lump("STTNUM" + str(nd))))
        hud_lumps.append(("YNUM" + str(nd), sprite_lump("STYSNUM" + str(nd))))   # pequeno amarelo (tem a arma)
        hud_lumps.append(("GNUM" + str(nd), sprite_lump("STGNUM" + str(nd))))    # pequeno cinza (nao tem)
    hud_lumps.append(("PRCNT", sprite_lump("STTPRCNT")))
    # rosto do Doomguy: 5 niveis de dano (saudavel -> quase morto) + morto
    FACES = ["STFST01", "STFST11", "STFST21", "STFST31", "STFST41"]
    for j in range(5):
        hud_lumps.append(("FACE" + str(j), sprite_lump(FACES[j])))
    hud_lumps.append(("FACED", sprite_lump("STFDEAD0")))

    # ---- SFX: banco de sons (DMX->PCM) + mapa evento->indice ----
    # o mapa evento->som e DADO (decidido aqui, lido do WAD oficial); o engine fica
    # generico (so toca o id que esta na tabela). 0xFFFF = som ausente -> engine ignora.
    SFX_PLAYER = ["DSPISTOL", "DSSHOTGN", "DSDOROPN", "DSDORCLS",
                  "DSITEMUP", "DSWPNUP", "DSPLPAIN", "DSPLDETH", "DSNOWAY"]
    SFX_MON = [   # por classe (zombie/shotgun/imp): sight, attack, pain, death
        ["DSPOSIT1", "DSPISTOL", "DSPOPAIN", "DSPODTH1"],
        ["DSPOSIT2", "DSSHOTGN", "DSPOPAIN", "DSPODTH2"],
        ["DSBGSIT1", "DSFIRSHT", "DSPOPAIN", "DSBGDTH1"],
    ]
    sfx_names = []
    sfx_index = {}

    def sfx_idx(name):
        if name is None or name not in wad.names:
            return NOTEX
        if name not in sfx_index:
            sfx_index[name] = len(sfx_names); sfx_names.append(name)
        return sfx_index[name]

    sfxmap = bytearray()
    for nm in SFX_PLAYER:
        sfxmap += struct.pack("<H", sfx_idx(nm))
    for cls in SFX_MON:
        for nm in cls:
            sfxmap += struct.pack("<H", sfx_idx(nm))
    # tabela de armas: por arma 2..7 -> ammoType, dmg, cone, cooldown, perShot, flashTh, sfxIdx (10 bytes)
    wtab = bytearray()
    for wn in range(2, 8):
        _, _, _, atype, dmg, cone, cd, pershot, flashth, sfxname = WEAPONS[wn]
        wtab += struct.pack("<BHHBBBH", atype, dmg, cone, cd, pershot, flashth, sfx_idx(sfxname))
    sfxb = bytearray(struct.pack("<H", len(sfx_names)))
    for nm in sfx_names:
        rate, pcm = load_sfx(wad, nm)
        sfxb += struct.pack("<HI", rate, len(pcm)) + pcm

    # ---- musica: lump MUS do mapa (D_<mapa>) -> MIDI tocado pelo Sequencer do host ----
    music = b""
    mus_name = "D_" + mapname
    if mus_name in wad.names:
        mid = mus2mid(wad.lump(mus_name))
        if mid:
            music = mid

    # ---- PAL0 + SINE ----
    pal0 = wad.lump("PLAYPAL")[:768]
    sine = bytearray()
    for j in range(1024):
        v = max(-32768, min(32767, int(round(math.sin(2 * math.pi * j / 1024) * 16384))))
        sine += struct.pack("<h", v)

    # ---- monta o PWAD ----
    lumps = [(mapname, b"")]
    for nm in GEO:
        lumps.append((nm, wad.lump(nm, i)))
    lumps += [("PAL0", bytes(pal0)), ("TEXMETA", bytes(texmeta)), ("TEXPIX", bytes(texpix)),
              ("SECT", bytes(sect)), ("LINE", bytes(line)), ("FLATPIX", bytes(flatpix)),
              ("LACT", bytes(lact)), ("STAG", bytes(stag)), ("LKEY", bytes(lkey)),
              ("SECGRID", bytes(secgrid)), ("HDR", hdr),
              ("FBALL", fireball), ("WTAB", bytes(wtab)),
              ("ITEMS", bytes(items)),
              ("SFXB", bytes(sfxb)), ("SFXMAP", bytes(sfxmap)), ("MUSIC", music),
              ("ENTS", bytes(ents)), ("MROT", bytes(mrot))] + weapon_lumps + mon_lumps + item_spr_lumps + hud_lumps + [("SINE", bytes(sine))]

    body = bytearray()
    directory = []
    for nm, data in lumps:
        pos = 12 + len(body)
        directory.append((pos if data else 12, len(data), nm))
        body += data
    diroff = 12 + len(body)
    out = bytearray(struct.pack("<4sii", b"PWAD", len(directory), diroff))
    out += body
    for fp, sz, nm in directory:
        out += struct.pack("<ii8s", fp, sz, nm.encode("latin1")[:8].ljust(8, b"\0"))

    sys.stderr.write(
        f"[wad2apex] {mapname}: {nsect} setores, {nline} linedefs, "
        f"{len(tex_order)} texturas ({len(texpix)}B), {len(flat_order)} flats ({len(flatpix)}B), "
        f"{len(sfx_names)} sfx ({len(sfxb)}B), musica {len(music)}B, "
        f"start_sec={start_sec} floor={start_floor}, PWAD {len(out)}B\n")
    return bytes(out)


def emit_apex(blobs, md5):
    """blobs: lista de (mapname, pwad_bytes). Um PWAD independente por mapa;
    cada mapa vira um chunks<n>() proprio (cabe no limite de 64KB/metodo do JVM)."""
    total = sum(len(b) for _, b in blobs)
    L = ["// GERADO por tools/wad2apex.py — NAO editar a mao.",
         f"// Fonte: DOOM1.WAD oficial (md5 {md5}).",
         f"// {len(blobs)} mapa(s): {', '.join(m for m, _ in blobs)}. PWADs {total} bytes.",
         "public class WadData {",
         f"    public static Integer mapCount() {{ return {len(blobs)}; }}",
         "    public static String mapName(Integer m) {"]
    for idx, (mn, _) in enumerate(blobs):
        L.append(f"        if (m == {idx}) return '{mn}';")
    L += ["        return '';", "    }"]
    for idx, (mn, blob) in enumerate(blobs):
        b64 = base64.b64encode(blob).decode("ascii")
        chunks = [b64[i:i + CHUNK] for i in range(0, len(b64), CHUNK)]
        L.append(f"    public static List<String> chunks{idx}() {{   // {mn}, {len(blob)} bytes")
        L.append("        List<String> c = new List<String>();")
        L += [f"        c.add('{ch}');" for ch in chunks]
        L += ["        return c;", "    }"]
    L.append("    public static List<String> chunks(Integer m) {")
    for idx in range(len(blobs)):
        L.append(f"        if (m == {idx}) return chunks{idx}();")
    L += ["        return chunks0();", "    }",
          "    public static String base64(Integer m) {",
          "        String s = '';",
          "        for (String c : chunks(m)) s += c;",
          "        return s;", "    }", "}"]
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("wad")
    ap.add_argument("maps", nargs="?", default="E1M1,E1M2,E1M3")   # ordem da progressao
    ap.add_argument("--out", default="-")
    a = ap.parse_args()
    wad = Wad(a.wad)
    mapnames = [m.strip() for m in a.maps.split(",") if m.strip()]
    blobs = []
    for mn in mapnames:
        if mn not in wad.names:
            sys.stderr.write(f"[wad2apex] mapa {mn} ausente no WAD, pulando\n")
            continue
        blobs.append((mn, build(wad, mn)))
    if not blobs:
        sys.stderr.write("[wad2apex] nenhum mapa valido\n"); sys.exit(1)
    apex = emit_apex(blobs, wad.md5)
    if a.out == "-":
        sys.stdout.write(apex)
    else:
        open(a.out, "w", newline="\n").write(apex)
        sys.stderr.write(f"[wad2apex] escrito {a.out}\n")


if __name__ == "__main__":
    main()
