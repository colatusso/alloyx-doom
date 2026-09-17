/**
 * Wad — parser de WAD do DOOM, em Apex puro.
 *
 * Le os bytes do PWAD oficial (embutidos em WadData via base64, ja que Apex nao
 * tem file I/O), faz o parsing real: header -> directory -> lumps. Extrai a
 * geometria do mapa (VERTEXES, LINEDEFS), o player start (THINGS) e a tabela de
 * seno (lump SINE). Sem bitwise/shift (nao suportados): tudo aritmetica inteira.
 */
public class Wad {
    public List<Integer> b;          // bytes crus (0..255)
    public Integer numLumps;
    public Integer dirOff;

    // vertices (paralelos)
    public List<Integer> vx = new List<Integer>();
    public List<Integer> vy = new List<Integer>();
    // linedefs (paralelos)
    public List<Integer> lv1 = new List<Integer>();
    public List<Integer> lv2 = new List<Integer>();
    public List<Integer> lflags = new List<Integer>();
    public List<Integer> ltwo = new List<Integer>();   // 1 = two-sided (portal), 0 = solido
    // player 1 start
    public Integer playerX;
    public Integer playerY;
    public Integer playerAng;        // graus DOOM (0=leste, 90=norte)
    // tabela de seno: 1024 amostras, sin*16384
    public List<Integer> sine = new List<Integer>();

    static final String AB =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

    // ---- base64 -> bytes (streaming, sem bitwise) ----
    public static List<Integer> decodeB64(String s) {
        List<Integer> out = new List<Integer>();
        Integer acc = 0;
        Integer bits = 0;
        for (Integer i = 0; i < s.length(); i++) {
            String c = s.substring(i, i + 1);
            if (c == '=') break;
            Integer v = AB.indexOf(c);
            if (v < 0) continue;
            acc = acc * 64 + v;
            bits += 6;
            if (bits >= 8) {
                Integer rem = bits - 8;
                Integer div = 1;
                for (Integer k = 0; k < rem; k++) div = div * 2;
                Integer byteVal = acc / div;
                out.add(Math.mod(byteVal, 256));
                acc = Math.mod(acc, div);
                bits = rem;
            }
        }
        return out;
    }

    // ---- leitura little-endian ----
    public Integer u16(Integer o) { return b.get(o) + b.get(o + 1) * 256; }
    public Integer s16(Integer o) {
        Integer v = u16(o);
        return (v >= 32768) ? v - 65536 : v;
    }
    public Integer u32(Integer o) {
        return b.get(o) + b.get(o + 1) * 256 + b.get(o + 2) * 65536 + b.get(o + 3) * 16777216;
    }

    // ---- directory: acha o offset da entry do lump pelo nome (ou -1) ----
    public List<Integer> codesOf(String name) {
        List<Integer> cs = new List<Integer>();
        for (Integer i = 0; i < name.length(); i++) { Integer ci = name.charAt(i) + 0; cs.add(ci); }
        return cs;
    }
    public Boolean nameEq(Integer off, List<Integer> want) {
        for (Integer k = 0; k < 8; k++) {
            Integer w = (k < want.size()) ? want.get(k) : 0;
            if (b.get(off + k) != w) return false;
        }
        return true;
    }
    /** retorna [filepos, size] do lump, ou null. */
    public List<Integer> findLump(String name) {
        List<Integer> want = codesOf(name);
        for (Integer i = 0; i < numLumps; i++) {
            Integer e = dirOff + i * 16;
            if (nameEq(e + 8, want)) {
                List<Integer> r = new List<Integer>();
                r.add(u32(e));
                r.add(u32(e + 4));
                return r;
            }
        }
        return null;
    }

    // ---- load + parse ----
    public void load() { loadMapIdx(0); }              // retrocompat (automap/fpv/demo)
    public void loadMapIdx(Integer mapIdx) {
        b = decodeB64(WadData.base64(mapIdx));
        numLumps = u32(4);
        dirOff = u32(8);
        vx = new List<Integer>(); vy = new List<Integer>();   // zera p/ recarregar outro mapa
        lv1 = new List<Integer>(); lv2 = new List<Integer>();
        lflags = new List<Integer>(); ltwo = new List<Integer>();
        sine = new List<Integer>();
        parseVertexes();
        parseLinedefs();
        parseThings();
        parseSine();
    }

    void parseVertexes() {
        List<Integer> L = findLump('VERTEXES');
        Integer fp = L.get(0);
        Integer n = L.get(1) / 4;
        for (Integer i = 0; i < n; i++) {
            vx.add(s16(fp + i * 4));
            vy.add(s16(fp + i * 4 + 2));
        }
    }
    void parseLinedefs() {
        List<Integer> L = findLump('LINEDEFS');
        Integer fp = L.get(0);
        Integer n = L.get(1) / 14;
        for (Integer i = 0; i < n; i++) {
            Integer o = fp + i * 14;
            lv1.add(u16(o));
            lv2.add(u16(o + 2));
            lflags.add(u16(o + 4));
            Integer back = u16(o + 12);
            ltwo.add((back == 65535) ? 0 : 1);
        }
    }
    void parseThings() {
        List<Integer> L = findLump('THINGS');
        Integer fp = L.get(0);
        Integer n = L.get(1) / 10;
        for (Integer i = 0; i < n; i++) {
            Integer o = fp + i * 10;
            Integer type = u16(o + 6);
            if (type == 1) {
                playerX = s16(o);
                playerY = s16(o + 2);
                playerAng = s16(o + 4);
                return;
            }
        }
    }
    void parseSine() {
        List<Integer> L = findLump('SINE');
        if (L == null) return;
        Integer fp = L.get(0);
        Integer n = L.get(1) / 2;
        for (Integer i = 0; i < n; i++) sine.add(s16(fp + i * 2));
    }

    // ---- self-test contra ground truth do E1M1 ----
    public static void run() {
        Wad w = new Wad();
        w.load();
        System.debug('lumps=' + w.numLumps + ' dirOff=' + w.dirOff + ' bytes=' + w.b.size());
        System.debug('VERTEXES=' + w.vx.size() + ' (esperado 467)');
        System.debug('LINEDEFS=' + w.lv1.size() + ' (esperado 475)');
        Integer solid = 0;
        for (Integer i = 0; i < w.ltwo.size(); i++) if (w.ltwo.get(i) == 0) solid++;
        System.debug('solidos(one-sided)=' + solid);
        System.debug('player start x=' + w.playerX + ' y=' + w.playerY + ' ang=' + w.playerAng + ' (esperado 1056,-3616,90)');
        System.debug('SINE n=' + w.sine.size() + ' sin[256]=' + w.sine.get(256) + ' (esperado ~16384) sin[0]=' + w.sine.get(0));
    }
}
