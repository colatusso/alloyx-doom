/**
 * Doom — renderer ASCII em Apex puro sobre a geometria do WAD oficial (E1M1).
 *
 * Dois modos:
 *   automap()  — top-down dos linedefs (prova a geometria real do WAD)
 *   fpv()      — raycaster first-person (grid de ocupacao + raymarch)
 *
 * Numerica 100% inteira (transpiler so tem int 32-bit, sem Long): trig por LUT
 * (lump SINE do WAD, escala S=16384), raymarch com produtos < 7e7 (sem overflow).
 * Cada linha do frame sai num System.debug; run.sh remove o prefixo "DEBUG|".
 */
public class Doom {
    static final Integer S = 16384;     // escala fixed-point do seno/cosseno
    static final Integer CELL = 16;     // tamanho da celula do grid (unidades DOOM)

    // ---- canvas de saida (ASCII automap/walkthrough) ----
    Integer cnvW;
    Integer cnvH;
    static final String PAL = ' .:-=+*#%@O';
    List<Integer> grid;

    // ---- bounds do mapa ----
    Integer minX;
    Integer minY;
    Integer maxXw;
    Integer maxYw;
    Integer gw;
    Integer gh;
    List<Integer> wall;                 // grid de ocupacao (1 = parede solida)

    Wad w;

    // ===================== infra de canvas =====================
    void canvas(Integer cw, Integer ch) {
        cnvW = cw; cnvH = ch;
        grid = new List<Integer>();
        for (Integer i = 0; i < cnvW * cnvH; i++) grid.add(0);
    }
    void put(Integer x, Integer y, Integer c) {
        if (x >= 0 && x < cnvW && y >= 0 && y < cnvH) grid.set(y * cnvW + x, c);
    }
    void draw() {
        for (Integer y = 0; y < cnvH; y++) {
            String row = '';
            for (Integer x = 0; x < cnvW; x++) {
                Integer c = grid.get(y * cnvW + x);
                row += PAL.substring(c, c + 1);
            }
            System.debug(row);
        }
    }
    void seg(Integer x0, Integer y0, Integer x1, Integer y1, Integer c) {
        Integer dx = Math.abs(x1 - x0);
        Integer dy = Math.abs(y1 - y0);
        Integer sx = (x0 < x1) ? 1 : -1;
        Integer sy = (y0 < y1) ? 1 : -1;
        Integer err = dx - dy;
        Integer x = x0;
        Integer y = y0;
        for (Integer g = 0; g < 8000; g++) {
            put(x, y, c);
            if (x == x1 && y == y1) return;
            Integer e2 = err * 2;
            if (e2 > -dy) { err -= dy; x += sx; }
            if (e2 < dx) { err += dx; y += sy; }
        }
    }

    // ===================== trig por LUT =====================
    Integer pmod(Integer a, Integer n) { Integer r = Math.mod(a, n); return (r < 0) ? r + n : r; }
    Integer sinT(Integer a) { return w.sine.get(pmod(a, 1024)); }
    Integer cosT(Integer a) { return w.sine.get(pmod(a + 256, 1024)); }

    // ===================== bounds / grid =====================
    void computeBounds() {
        minX = w.vx.get(0); Integer maxX = minX;
        minY = w.vy.get(0); Integer maxY = minY;
        for (Integer i = 1; i < w.vx.size(); i++) {
            Integer X = w.vx.get(i); Integer Y = w.vy.get(i);
            if (X < minX) minX = X; if (X > maxX) maxX = X;
            if (Y < minY) minY = Y; if (Y > maxY) maxY = Y;
        }
        maxXw = maxX; maxYw = maxY;
        gw = (maxX - minX) / CELL + 2;
        gh = (maxY - minY) / CELL + 2;
    }
    Integer cellX(Integer x) { return (x - minX) / CELL; }
    Integer cellY(Integer y) { return (y - minY) / CELL; }
    void rasterizeWalls() {
        wall = new List<Integer>();
        for (Integer i = 0; i < gw * gh; i++) wall.add(0);
        for (Integer i = 0; i < w.lv1.size(); i++) {
            if (w.ltwo.get(i) != 0) continue;             // so paredes solidas (one-sided)
            Integer a = w.lv1.get(i); Integer b = w.lv2.get(i);
            bresenhamWall(cellX(w.vx.get(a)), cellY(w.vy.get(a)),
                          cellX(w.vx.get(b)), cellY(w.vy.get(b)));
        }
    }
    void bresenhamWall(Integer x0, Integer y0, Integer x1, Integer y1) {
        Integer dx = Math.abs(x1 - x0);
        Integer dy = Math.abs(y1 - y0);
        Integer sx = (x0 < x1) ? 1 : -1;
        Integer sy = (y0 < y1) ? 1 : -1;
        Integer err = dx - dy;
        Integer x = x0;
        Integer y = y0;
        for (Integer g = 0; g < 8000; g++) {
            if (x >= 0 && x < gw && y >= 0 && y < gh) wall.set(y * gw + x, 1);
            if (x == x1 && y == y1) return;
            Integer e2 = err * 2;
            if (e2 > -dy) { err -= dy; x += sx; }
            if (e2 < dx) { err += dx; y += sy; }
        }
    }
    Boolean isWall(Integer x, Integer y) {
        Integer cx = cellX(x); Integer cy = cellY(y);
        if (cx < 0 || cx >= gw || cy < 0 || cy >= gh) return true;   // fora do mapa = parede
        return wall.get(cy * gw + cx) == 1;
    }

    // ===================== AUTOMAP =====================
    public static void automap() {
        Doom d = new Doom();
        d.w = new Wad(); d.w.load();
        d.computeBounds();
        d.canvas(100, 46);
        Integer spanX = Math.max(1, (d.gw - 2) * CELL);
        Integer spanY = Math.max(1, (d.gh - 2) * CELL);
        for (Integer i = 0; i < d.w.lv1.size(); i++) {
            Integer a = d.w.lv1.get(i); Integer b = d.w.lv2.get(i);
            Integer ax = (d.w.vx.get(a) - d.minX) * 99 / spanX;
            Integer ay = (spanY - (d.w.vy.get(a) - d.minY)) * 45 / spanY;
            Integer bx = (d.w.vx.get(b) - d.minX) * 99 / spanX;
            Integer by = (spanY - (d.w.vy.get(b) - d.minY)) * 45 / spanY;
            d.seg(ax, ay, bx, by, (d.w.ltwo.get(i) == 0) ? 7 : 2);
        }
        Integer px = (d.w.playerX - d.minX) * 99 / spanX;
        Integer py = (spanY - (d.w.playerY - d.minY)) * 45 / spanY;
        d.put(px, py, 10);
        System.debug('E1M1 automap — ' + d.w.lv1.size() + ' linedefs (WAD oficial)');
        d.draw();
    }

    // ===================== FIRST-PERSON RAYCASTER =====================
    // VW/VH sao por-instancia pra caber no terminal (run.sh mede e passa o tamanho).
    Integer VW = 80;                     // largura do view (colunas)
    Integer VH = 22;                     // altura do view (linhas)
    static final Integer FOV = 182;      // ~64 graus em unidades de 1024/circulo
    static final Integer STEP = 6;       // passo do raymarch (unidades)
    static final Integer MAXD = 6000;    // alcance maximo (cobre o E1M1 inteiro)
    static final Integer TURNV = 9;      // giro por frame no modo jogavel (~190 graus/s a 60fps)
    static final Integer MOVEV = 15;     // avanco por frame no modo jogavel
    static final Integer ENSPD = 5;      // velocidade dos monstros (perseguicao)
    static final Integer DTICKS = 5;     // frames por quadro da animacao de morte
    static final Integer ATKCD = 80;     // cooldown de ataque do inimigo (frames)
    static final Integer WAKEDIST = 750; // so acorda com linha de visao dentro disso
    static final Integer ATKRANGE = 700; // alcance de ataque

    /** renderiza um frame a partir de (px,py) olhando pra angTab (unidades 1024/circulo) */
    void renderView(Integer px, Integer py, Integer angTab) {
        canvas(VW, VH);
        Integer wallk = VH * 590;        // projecao da altura, proporcional ao tamanho do view
        for (Integer col = 0; col < VW; col++) {
            Integer aoff = (col - VW / 2) * FOV / VW;
            Integer ray = angTab - aoff;
            Integer dx = cosT(ray);
            Integer dy = sinT(ray);
            // raymarch, lembrando a celula anterior pra deduzir a face atingida
            Integer hitM = MAXD;
            Integer pcx = cellX(px);
            Integer pcy = cellY(py);
            Integer face = 0;                          // 0 = N/S (clara), 1 = L/O (escura)
            for (Integer m = STEP; m < MAXD; m += STEP) {
                Integer wx = px + dx * m / S;
                Integer wy = py + dy * m / S;
                Integer cx = cellX(wx);
                Integer cy = cellY(wy);
                if (isWall(wx, wy)) {
                    face = (cx != pcx) ? 1 : 0;
                    hitM = m;
                    break;
                }
                pcx = cx; pcy = cy;
            }
            // correcao fisheye + altura
            Integer perp = hitM * cosT(aoff) / S;
            if (perp < 1) perp = 1;
            Integer h = wallk / perp;
            if (h > VH - 4) h = VH - 4;   // sempre deixa faixa de teto/chao -> todo frame le como 3D
            // sombreamento por distancia, paredes L/O um degrau mais escuras
            Integer sh = 9 - perp / 150 - face;
            if (sh < 2) sh = 2;
            if (sh > 9) sh = 9;
            Integer top = (VH - h) / 2;
            for (Integer y = 0; y < VH; y++) {
                Integer c;
                if (y < top) c = 0;                       // ceu
                else if (y < top + h) c = sh;             // parede
                else c = 1;                               // chao
                put(col, y, c);
            }
        }
    }

    public static void fpv() {
        Doom d = new Doom();
        d.w = new Wad(); d.w.load();
        d.computeBounds();
        d.rasterizeWalls();
        Integer ang = d.w.playerAng * 1024 / 360;
        System.debug('E1M1 first-person @ start (' + d.w.playerX + ',' + d.w.playerY + ') ang=' + d.w.playerAng);
        d.renderView(d.w.playerX, d.w.playerY, ang);
        d.draw();
    }

    /** distancia ate a parede ao longo de um angulo (raymarch de um raio so) */
    Integer rayDist(Integer px, Integer py, Integer ang) {
        Integer dx = cosT(ang);
        Integer dy = sinT(ang);
        for (Integer m = STEP; m < MAXD; m += STEP) {
            if (isWall(px + dx * m / S, py + dy * m / S)) return m;
        }
        return MAXD;
    }
    /** angulo (em unidades 1024) com mais espaco livre a partir de (px,py) */
    Integer openestAngle(Integer px, Integer py) {
        Integer best = 0; Integer bestD = -1;
        for (Integer a = 0; a < 1024; a += 64) {
            Integer dd = rayDist(px, py, a);
            if (dd > bestD) { bestD = dd; best = a; }
        }
        return best;
    }

    // ---- bot que percorre o nivel sozinho (sem rota hardcoded) ----
    static final Integer FRAMES = 160;
    static final Integer MOVE = 26;      // avanco por frame (unidades)
    static final Integer PAN = 7;        // pan continuo por frame (~2.5 graus)

    public static void demo() {
        Doom d = new Doom();
        d.w = new Wad(); d.w.load();
        d.computeBounds();
        d.rasterizeWalls();
        Integer px = d.w.playerX;
        Integer py = d.w.playerY;
        Integer ang = d.openestAngle(px, py);   // comeca virado pro corredor mais aberto

        for (Integer f = 0; f < FRAMES; f++) {
            d.renderView(px, py, ang);
            System.debug('@@F@@');
            Integer hp = 100 - Math.mod(f, 7) * 2;
            System.debug(' DOOM  E1M1: Hangar    POS ' + px + ',' + py +
                         '   FACE ' + (ang * 360 / 1024) + '    HEALTH ' + hp +
                         '%    FRAME ' + (f + 1) + '/' + FRAMES);
            d.draw();

            // camera autonoma: caminha pelos corredores mantendo standoff das paredes
            // (centraliza) e mira sempre rumo ao espaco aberto. Sem rota hardcoded.
            Integer fwd = d.rayDist(px, py, ang);
            Integer lf = d.rayDist(px, py, ang + 256);   // 90 graus esquerda
            Integer rt = d.rayDist(px, py, ang - 256);   // 90 graus direita
            // centraliza no corredor: empurra pra longe da parede lateral mais proxima
            Integer D = 90;
            if (lf < D) { Integer adj = (D - lf) / 2; px += d.cosT(ang - 256) * adj / S; py += d.sinT(ang - 256) * adj / S; }
            if (rt < D) { Integer adj = (D - rt) / 2; px += d.cosT(ang + 256) * adj / S; py += d.sinT(ang + 256) * adj / S; }
            // direcao: se ha corredor a frente segue (com leve correcao p/ o lado mais aberto);
            // se nao, re-mira pro angulo mais aberto (escapa de becos)
            if (fwd > 150) {
                if (lf - rt > 80) ang = d.pmod(ang + 12, 1024);
                else if (rt - lf > 80) ang = d.pmod(ang - 12, 1024);
                Integer nx = px + d.cosT(ang) * MOVE / S;
                Integer ny = py + d.sinT(ang) * MOVE / S;
                if (d.rayDist(nx, ny, ang) > 60) { px = nx; py = ny; }   // so anda com margem
            } else {
                ang = d.openestAngle(px, py);
            }
        }
    }

    // ===================== API GRAFICA (host Java em tempo real) =====================
    // O engine Apex calcula um framebuffer RGB; o host Java abre a janela, le o
    // teclado e desenha os pixels. Estado do jogador vive aqui (no Apex).
    Integer gpx;        // posicao X do jogador
    Integer gpy;        // posicao Y do jogador
    Integer gang;       // angulo (unidades 1024/circulo)
    List<Integer> fb;   // framebuffer RGB 0xRRGGBB (VW*VH), reusado entre frames

    // geometria vetorial de TODAS as linhas (one-sided + two-sided) p/ portal walk
    List<Integer> lax; List<Integer> lay;     // ponto inicial (v1)
    List<Integer> lex; List<Integer> ley;     // vetor da linha (v2-v1)
    List<Integer> lLen;                        // comprimento de cada linha
    Integer nlines;

    // setores (paralelos): altura/luz/flats/ceu por setor
    List<Integer> secFloor; List<Integer> secCeil; List<Integer> secLight;
    List<Integer> secFloorFlat; List<Integer> secCeilFlat; List<Integer> secSky;
    List<Integer> secOpenCeil;                 // teto-alvo quando a porta abre
    List<Integer> secDoor; List<Integer> secDoorT;   // estado de porta: 0 parado/1 abrindo/2 espera/3 fechando + timer
    // linedefs: setor e texturas (upper/mid/lower) de cada lado + xoffset + special
    List<Integer> lFrontSec; List<Integer> lBackSec;
    List<Integer> lfUp; List<Integer> lfMid; List<Integer> lfLo;
    List<Integer> lbUp; List<Integer> lbMid; List<Integer> lbLo;
    List<Integer> lfX; List<Integer> lbX; List<Integer> lDoor;
    // specials de gameplay: acao/trigger/tag por linha + tag/floor-vizinho/plataforma por setor
    List<Integer> lAct; List<Integer> lTrig; List<Integer> lTag; List<Integer> lKey;
    List<Integer> secTag; List<Integer> secLowFloor;
    List<Integer> secPlat; List<Integer> secPlatT; List<Integer> secPlatHigh;
    Integer prevX; Integer prevY; Integer exitT;       // pos anterior (cruzamento) + flash de saida
    Integer curMap;                                    // indice do mapa atual (multi-mapa)
    // grid de setores (BSP) p/ olho dinamico e colisao de altura
    List<Integer> secGrid; Integer sgw; Integer sgh; Integer playerSec;

    // texturas reais do WAD
    List<Integer> pal;                        // paleta 0: 256 cores 0xRRGGBB
    List<Integer> tW; List<Integer> tH; List<Integer> tOff;   // metadados por textura
    Integer texpixFp;                         // offset do lump TEXPIX dentro de w.b
    Integer flatFp;                           // offset do lump FLATPIX (flats 64x64) em w.b
    Integer skyTexIdx;                        // indice da textura de ceu (SKY1)
    Integer eyeBaseFloor;                     // altura do chao do setor do start
    Integer eyeZ;                             // altura do olho (eyeBaseFloor + 41)
    Integer horiz;                            // linha do horizonte (VH/2)
    Integer projS;                            // escala de projecao (derivada do FOV)

    // armas: data-driven (6 armas x 3 sprites em gunW/gunH/gunPix, base=(arma-2)*3) + tabela WTAB
    List<Integer> gunW; List<Integer> gunH; List<Integer> gunPix;   // 'gunW': 'gW' colidiria com o grid 'gw'
    Integer fireTimer;                        // frames restantes da animacao de disparo
    Integer curWeap;                          // arma atual (2..7)
    List<Integer> ownWeap;                    // arma possuida? (indices 2..7; 0/1)
    List<Integer> wAmmoType; List<Integer> wDmg; List<Integer> wCone;   // tabela por arma (indices 2..7)
    List<Integer> wCd; List<Integer> wPerShot; List<Integer> wFlashTh; List<Integer> wSfx;
    Integer rockets; Integer cells;           // municao de foguetes/celulas
    static final Integer MAXROK = 50; static final Integer MAXCEL = 300;
    List<Integer> zbuf;                       // distancia perp por coluna (occlusao de sprites)
    Integer wallk;                            // constante de projecao de altura (VH*620)

    // itens (pickups): spawn + sprite + categoria/efeito + pego
    List<Integer> itX; List<Integer> itY; List<Integer> itSpr;
    List<Integer> itCat; List<Integer> itAmt; List<Integer> itGot;
    Integer nitems;
    List<Integer> isW; List<Integer> isH; List<Integer> isPix;   // sprites de item

    // monstros: spawns + estado + sprites (vivo/morte) por classe (0=zombie,1=shotgun,2=imp)
    List<Integer> enX; List<Integer> enY; List<Integer> enCls;
    List<Integer> enFx; List<Integer> enFy;            // vetor de facing (escala S) p/ escolher a rotacao
    List<Integer> enDropC; List<Integer> enDropA;      // drop ao morrer: categoria (255=nada) + quantidade
    List<Integer> enState; List<Integer> enHP;         // estado: 0=vivo 1=morrendo 2=corpo
    List<Integer> enDF; List<Integer> enDT;            // frame de morte (0..4) + timer
    List<Integer> enAtk;                               // cooldown de ataque
    List<Integer> enAtkT;                              // timer da pose de ataque (frames mostrando o disparo)
    List<Integer> enWake;                              // 0=dormindo 1=acordado (viu o player)
    Integer nent;
    Integer tick;                                      // contador de frames (pra mira aleatoria)
    List<Integer> idleW; List<Integer> idleH; List<Integer> idlePix;   // idle: 3 classes * 5 rot fisicas
    List<Integer> walkW; List<Integer> walkH; List<Integer> walkPix;   // walk: 3 classes * 5 rot fisicas
    List<Integer> monKW; List<Integer> monKH; List<Integer> monKPix;   // ataque (frontal, 3)
    List<Integer> monDW; List<Integer> monDH; List<Integer> monDPix;   // morte (3*5)
    List<Integer> rotPhys; List<Integer> rotMir;                       // rot 0..7 -> indice fisico + espelho
    // projeteis (bola de fogo do imp): slots fixos, prjLife<=0 = inativo
    static final Integer MAXPROJ = 48;
    static final Integer PROJSPD = 22;
    List<Integer> prjX; List<Integer> prjY; List<Integer> prjZ;
    List<Integer> prjVx; List<Integer> prjVy; List<Integer> prjLife;
    Integer fbW; Integer fbH; Integer fbPix;                            // sprite da bola (fbPix=-1 se ausente)

    // jogador + HUD
    Integer hp; Integer bullets; Integer shells; Integer flashT; Integer invT;   // vida, municoes, flash, invuln
    static final Integer MAXBUL = 200; static final Integer MAXSHL = 50;
    List<Integer> hasKey;                              // chaves do nivel: [azul, amarelo, vermelho] (0/1)
    Integer spawnX; Integer spawnY; Integer spawnAng;
    Integer armor;                                     // armadura (sem pickups -> 0, layout fiel)
    Boolean useHeld;                                   // borda da tecla USE (nao re-aciona segurando)
    Integer hudH;                                      // altura da barra de HUD
    Integer sbW; Integer sbH; Integer sbPix;           // STBAR real (fundo da barra)
    Integer saW; Integer saH; Integer saPix;           // STARMS (painel "ARMS")
    List<Integer> numW; List<Integer> numH; List<Integer> numPix;      // digitos grandes 0-9
    List<Integer> ynW; List<Integer> ynH; List<Integer> ynPix;         // pequenos amarelos (arma que tem)
    List<Integer> gnW; List<Integer> gnH; List<Integer> gnPix;         // pequenos cinza (arma que nao tem)
    Integer pcW; Integer pcH; Integer pcPix;           // '%'
    List<Integer> faW; List<Integer> faH; List<Integer> faPix;         // rosto: 5 niveis de dano
    Integer fdW; Integer fdH; Integer fdPix;           // rosto morto

    // audio: fila de eventos [sfxId, vol] drenada pelo host por frame + mapa evento->id
    List<Integer> sndQ;
    Integer sfxPistol; Integer sfxShotgun; Integer sfxDoorOpen; Integer sfxDoorClose;
    Integer sfxItem; Integer sfxWeapon; Integer sfxPain; Integer sfxDeath; Integer sfxNoWay;
    List<Integer> monSight; List<Integer> monAtk; List<Integer> monPain; List<Integer> monDeath;

    /** inicializa buffers + estado do player (1x) e carrega o 1o mapa */
    public void init(Integer vw, Integer vh) {
        VW = vw; VH = vh;
        horiz = VH / 2;
        wallk = VH * 620;        // legado (modo ASCII/sprites)
        hudH = VW / 10;          // STBAR e 320x32 -> escalado pra VW da' VW/10 de altura
        fb = new List<Integer>();
        for (Integer i = 0; i < VW * VH; i++) fb.add(0);
        zbuf = new List<Integer>();
        for (Integer i = 0; i < VW; i++) zbuf.add(MAXD);
        sndQ = new List<Integer>();
        prjX = new List<Integer>(); prjY = new List<Integer>(); prjZ = new List<Integer>();
        prjVx = new List<Integer>(); prjVy = new List<Integer>(); prjLife = new List<Integer>();
        for (Integer i = 0; i < MAXPROJ; i++) {
            prjX.add(0); prjY.add(0); prjZ.add(0); prjVx.add(0); prjVy.add(0); prjLife.add(0);
        }
        // estado do player (persiste entre mapas; so reseta na morte)
        hp = 100; bullets = 50; shells = 0; rockets = 0; cells = 0; armor = 0; curWeap = 2;
        ownWeap = new List<Integer>();
        for (Integer k = 0; k < 8; k++) ownWeap.add(0);
        ownWeap.set(2, 1);                                 // comeca com a pistola
        hasKey = new List<Integer>(); hasKey.add(0); hasKey.add(0); hasKey.add(0);
        curMap = 0;
        loadMap(0);
    }

    /** carrega o mapa n (geometria/texturas/spawns) preservando o estado do player */
    void loadMap(Integer n) {
        curMap = n;
        w = new Wad(); w.loadMapIdx(n);
        computeBounds();
        rasterizeWalls();        // grid p/ colisao (paredes one-sided)
        buildLineGeom();         // geometria vetorial de TODAS as linhas
        parsePalette();          // PAL0
        parseTextures();         // TEXMETA + TEXPIX
        parseHdr();              // altura do olho + indice do ceu
        parseSect();             // setores (altura/luz/flats)
        parseLine();             // linedefs (setor/textura por lado)
        parseLact();             // specials de gameplay por linha (lift/floor/exit)
        parseStag();             // tag + floor vizinho + estado de plataforma por setor
        parseFlats();            // FLATPIX (flats 64x64)
        parseSecGrid();          // setor por celula (olho dinamico + colisao)
        parseGun();              // sprites das armas (pistola + shotgun)
        parseFireball();         // sprite da bola de fogo do imp
        parseItems();            // spawns de itens (THINGS)
        parseItemSprites();      // sprites dos itens
        parseEnts();             // spawns de monstros (THINGS)
        parseMon();              // sprites dos monstros (vivo + morte)
        parseHud();              // digitos, %, rostos
        parseSfxMap();           // mapa evento->id de som (o PCM fica no banco SFXB)
        spawnX = w.playerX; spawnY = w.playerY; spawnAng = w.playerAng * 1024 / 360;
        gpx = spawnX; gpy = spawnY; gang = spawnAng;
        prevX = gpx; prevY = gpy;
        playerSec = -1; useHeld = false;
        projS = (VW / 2) * cosT(FOV / 2) / sinT(FOV / 2);   // projecao consistente c/ o FOV
        eyeZ = eyeBaseFloor + 41;                           // altura do olho (estilo DOOM)
        invT = 30; tick = 0; exitT = 0; fireTimer = 0; flashT = 0;
        hasKey.set(0, 0); hasKey.set(1, 0); hasKey.set(2, 0);     // chaves sao por-nivel
        for (Integer p = 0; p < MAXPROJ; p++) prjLife.set(p, 0);   // limpa projeteis do mapa anterior
    }

    /** avanca pro proximo mapa na saida do nivel (preserva vida/armas/municao) */
    void nextMap() {
        Integer nx = curMap + 1;
        if (nx >= WadData.mapCount()) nx = 0;               // apos o ultimo, volta ao 1o
        loadMap(nx);
    }
    void parseFireball() {
        List<Integer> L = w.findLump('FBALL');
        if (L == null || L.get(1) == 0) { fbPix = -1; return; }     // sem sprite -> imp volta a hitscan
        Integer fp = L.get(0);
        fbW = w.u16(fp); fbH = w.u16(fp + 2); fbPix = fp + 8;
    }
    /** imp lanca uma bola de fogo mirando o player (slot livre nos projeteis) */
    void spawnFireball(Integer i) {
        if (fbPix < 0) return;
        Integer slot = -1;
        for (Integer p = 0; p < MAXPROJ; p++) if (prjLife.get(p) <= 0) { slot = p; break; }
        if (slot < 0) return;
        Integer ex = enX.get(i); Integer ey = enY.get(i);
        Integer vx = gpx - ex; Integer vy = gpy - ey;
        Integer L = isqrt(vx * vx + vy * vy); if (L < 1) L = 1;
        prjX.set(slot, ex); prjY.set(slot, ey);
        prjZ.set(slot, spriteFloor(ex, ey) + 32);                   // ~peito do imp
        prjVx.set(slot, vx * PROJSPD / L); prjVy.set(slot, vy * PROJSPD / L);
        prjLife.set(slot, 110);
    }
    /** move os projeteis: some na parede, expira, ou acerta o player (dano) */
    void updateProjectiles() {
        for (Integer p = 0; p < MAXPROJ; p++) {
            if (prjLife.get(p) <= 0) continue;
            Integer nx = prjX.get(p) + prjVx.get(p);
            Integer ny = prjY.get(p) + prjVy.get(p);
            if (isWall(nx, ny)) { prjLife.set(p, 0); continue; }
            prjX.set(p, nx); prjY.set(p, ny);
            prjLife.set(p, prjLife.get(p) - 1);
            Integer rx = gpx - nx; Integer ry = gpy - ny;
            if (rx * rx + ry * ry < 1600) {                         // 40^2: acertou o player
                if (invT == 0) { hp -= 12; flashT = 8; if (hp > 0) playSfx(sfxPain, 255); }
                prjLife.set(p, 0);
            }
        }
    }
    /** bola de fogo como billboard brilhante (centrada na altura do voo), oclusao por zbuf */
    void renderProjectiles() {
        if (fbPix < 0) return;
        Integer dirX = cosT(gang); Integer dirY = sinT(gang);
        for (Integer p = 0; p < MAXPROJ; p++) {
            if (prjLife.get(p) <= 0) continue;
            Integer rx = prjX.get(p) - gpx; Integer ry = prjY.get(p) - gpy;
            Integer depth = (rx * dirX + ry * dirY) / S;
            if (depth < 16) continue;
            Integer side = (rx * dirY - ry * dirX) / S;
            Integer screenCol = VW / 2 + side * projS / depth;
            Integer ssH = fbH * projS / depth; if (ssH < 1) continue;
            Integer ssW = ssH * fbW / fbH;
            Integer baseRow = horiz + (eyeZ - prjZ.get(p)) * projS / depth;
            Integer top = baseRow - ssH / 2; Integer left = screenCol - ssW / 2;
            blitBillboard(fbW, fbH, fbPix, ssW, ssH, left, top, depth, 256);
        }
    }

    // ===================== AUDIO (host toca; o engine so enfileira eventos) =====================
    /** banco de SFX cru (lump SFXB: [u16 n] + por som [u16 rate][u32 len][pcm 8-bit]);
     *  o host monta os Clips a partir disso, uma vez no init. */
    public List<Integer> audioBank() {
        List<Integer> out = new List<Integer>();
        List<Integer> L = w.findLump('SFXB');
        if (L == null) return out;
        Integer fp = L.get(0); Integer sz = L.get(1);
        for (Integer i = 0; i < sz; i++) out.add(w.b.get(fp + i));
        return out;
    }
    /** indice do mapa atual — o host observa isso p/ trocar a musica na transicao */
    public Integer mapIdx() { return curMap; }
    /** musica do mapa em bytes MIDI (lump MUSIC, MUS->MIDI no gerador); o host toca em loop */
    public List<Integer> musicBank() {
        List<Integer> out = new List<Integer>();
        List<Integer> L = w.findLump('MUSIC');
        if (L == null) return out;
        Integer fp = L.get(0); Integer sz = L.get(1);
        for (Integer i = 0; i < sz; i++) out.add(w.b.get(fp + i));
        return out;
    }
    /** eventos de som desde o ultimo frame: pares [sfxId, vol(0..255)]; drena a fila */
    public List<Integer> soundEvents() {
        List<Integer> q = sndQ;
        sndQ = new List<Integer>();
        return q;
    }
    void playSfx(Integer sid, Integer vol) {
        if (sid == 65535 || vol <= 0) return;        // 0xFFFF = som ausente no WAD
        if (vol > 255) vol = 255;
        sndQ.add(sid); sndQ.add(vol);
    }
    /** atenua o volume pela distancia (corta alem do alcance audivel ~1600u) */
    Integer sfxVolDist(Integer dd) {
        Integer v = 255 - 255 * dd / 1600;
        return (v < 0) ? 0 : v;
    }
    /** mapa evento->id de som: 8 slots do player + 4 por classe de monstro */
    void parseSfxMap() {
        List<Integer> L = w.findLump('SFXMAP');
        if (L == null) return;
        Integer fp = L.get(0);
        sfxPistol = w.u16(fp); sfxShotgun = w.u16(fp + 2);
        sfxDoorOpen = w.u16(fp + 4); sfxDoorClose = w.u16(fp + 6);
        sfxItem = w.u16(fp + 8); sfxWeapon = w.u16(fp + 10);
        sfxPain = w.u16(fp + 12); sfxDeath = w.u16(fp + 14); sfxNoWay = w.u16(fp + 16);
        monSight = new List<Integer>(); monAtk = new List<Integer>();
        monPain = new List<Integer>(); monDeath = new List<Integer>();
        Integer base = fp + 18;
        for (Integer c = 0; c < 3; c++) {
            Integer o = base + c * 8;
            monSight.add(w.u16(o)); monAtk.add(w.u16(o + 2));
            monPain.add(w.u16(o + 4)); monDeath.add(w.u16(o + 6));
        }
    }

    void parseEnts() {
        Integer fp = w.findLump('ENTS').get(0);
        nent = w.u16(fp);
        enX = new List<Integer>(); enY = new List<Integer>(); enCls = new List<Integer>();
        enFx = new List<Integer>(); enFy = new List<Integer>();
        enDropC = new List<Integer>(); enDropA = new List<Integer>();
        enState = new List<Integer>(); enHP = new List<Integer>();
        enDF = new List<Integer>(); enDT = new List<Integer>(); enAtk = new List<Integer>();
        enAtkT = new List<Integer>(); enWake = new List<Integer>();
        for (Integer i = 0; i < nent; i++) {
            Integer o = fp + 2 + i * 8;
            Integer cls = w.u16(o + 4);
            Integer ex = w.s16(o); Integer ey = w.s16(o + 2);
            enX.add(ex); enY.add(ey); enCls.add(cls);
            enDropC.add(w.b.get(o + 6)); enDropA.add(w.b.get(o + 7));
            // facing inicial: aponta pro player start (normalizado em escala S)
            Integer vfx = w.playerX - ex; Integer vfy = w.playerY - ey;
            Integer lf = isqrt(vfx * vfx + vfy * vfy); if (lf < 1) lf = 1;
            enFx.add(vfx * S / lf); enFy.add(vfy * S / lf);
            enState.add(0); enDF.add(0); enDT.add(0); enAtkT.add(0); enWake.add(0);
            enAtk.add(Math.mod(i * 17, ATKCD));          // escalona p/ nao atacarem todos juntos
            enHP.add(cls == 0 ? 20 : (cls == 1 ? 30 : 60));   // zombie/shotgun/imp
        }
    }
    void parseMon() {
        idleW = new List<Integer>(); idleH = new List<Integer>(); idlePix = new List<Integer>();
        walkW = new List<Integer>(); walkH = new List<Integer>(); walkPix = new List<Integer>();
        monKW = new List<Integer>(); monKH = new List<Integer>(); monKPix = new List<Integer>();
        monDW = new List<Integer>(); monDH = new List<Integer>(); monDPix = new List<Integer>();
        for (Integer c = 0; c < 3; c++) {
            for (Integer p = 0; p < 5; p++) {                         // 5 rotacoes fisicas por frame
                Integer ia = w.findLump('MIA' + c + '' + p).get(0);
                idleW.add(w.u16(ia)); idleH.add(w.u16(ia + 2)); idlePix.add(ia + 8);
                Integer ib = w.findLump('MIB' + c + '' + p).get(0);
                walkW.add(w.u16(ib)); walkH.add(w.u16(ib + 2)); walkPix.add(ib + 8);
            }
            Integer kk = w.findLump('MONK' + c).get(0);
            monKW.add(w.u16(kk)); monKH.add(w.u16(kk + 2)); monKPix.add(kk + 8);
            for (Integer f = 0; f < 5; f++) {
                Integer e = w.findLump('MOND' + c + '' + f).get(0);   // MOND<c><f>
                monDW.add(w.u16(e)); monDH.add(w.u16(e + 2)); monDPix.add(e + 8);
            }
        }
        rotPhys = new List<Integer>(); rotMir = new List<Integer>();
        Integer mr = w.findLump('MROT').get(0);
        for (Integer k = 0; k < 8; k++) { rotPhys.add(w.b.get(mr + k * 2)); rotMir.add(w.b.get(mr + k * 2 + 1)); }
    }
    /** rotacao 0..7 do sprite: octante entre o facing do monstro e a direcao p/ a camera */
    Integer spriteRot(Integer i) {
        Integer vx = gpx - enX.get(i); Integer vy = gpy - enY.get(i);   // monstro -> camera
        Integer fx = enFx.get(i); Integer fy = enFy.get(i);
        Integer along = (vx * fx + vy * fy) / S;
        Integer perp = (vx * fy - vy * fx) / S;
        Integer bestK = 0; Integer best = -2000000000;
        for (Integer k = 0; k < 8; k++) {
            Integer dk = along * cosT(k * 128) + perp * sinT(k * 128);
            if (dk > best) { best = dk; bestK = k; }
        }
        return bestK;
    }
    void parseHud() {
        numW = new List<Integer>(); numH = new List<Integer>(); numPix = new List<Integer>();
        ynW = new List<Integer>(); ynH = new List<Integer>(); ynPix = new List<Integer>();
        gnW = new List<Integer>(); gnH = new List<Integer>(); gnPix = new List<Integer>();
        for (Integer d = 0; d < 10; d++) {
            Integer fp = w.findLump('NUM' + d).get(0);
            numW.add(w.u16(fp)); numH.add(w.u16(fp + 2)); numPix.add(fp + 8);
            Integer yp = w.findLump('YNUM' + d).get(0);
            ynW.add(w.u16(yp)); ynH.add(w.u16(yp + 2)); ynPix.add(yp + 8);
            Integer gp = w.findLump('GNUM' + d).get(0);
            gnW.add(w.u16(gp)); gnH.add(w.u16(gp + 2)); gnPix.add(gp + 8);
        }
        Integer p = w.findLump('PRCNT').get(0); pcW = w.u16(p); pcH = w.u16(p + 2); pcPix = p + 8;
        Integer sbo = w.findLump('STBAR').get(0); sbW = w.u16(sbo); sbH = w.u16(sbo + 2); sbPix = sbo + 8;
        Integer sao = w.findLump('STARMS').get(0); saW = w.u16(sao); saH = w.u16(sao + 2); saPix = sao + 8;
        faW = new List<Integer>(); faH = new List<Integer>(); faPix = new List<Integer>();
        for (Integer j = 0; j < 5; j++) {
            Integer f = w.findLump('FACE' + j).get(0);
            faW.add(w.u16(f)); faH.add(w.u16(f + 2)); faPix.add(f + 8);
        }
        Integer g = w.findLump('FACED').get(0); fdW = w.u16(g); fdH = w.u16(g + 2); fdPix = g + 8;
    }

    void parseGun() {
        gunW = new List<Integer>(); gunH = new List<Integer>(); gunPix = new List<Integer>();
        for (Integer wn = 2; wn < 8; wn++) {                  // armas 2..7, 3 sprites (idle/fire/flash)
            parseGunLump('WP' + wn + 'I');
            parseGunLump('WP' + wn + 'F');
            parseGunLump('WP' + wn + 'L');
        }
        // tabela WTAB: 10 bytes por arma (ammoType, dmg, cone, cd, perShot, flashTh, sfx)
        wAmmoType = new List<Integer>(); wDmg = new List<Integer>(); wCone = new List<Integer>();
        wCd = new List<Integer>(); wPerShot = new List<Integer>(); wFlashTh = new List<Integer>(); wSfx = new List<Integer>();
        Integer tp = w.findLump('WTAB').get(0);
        for (Integer k = 0; k < 6; k++) {
            Integer o = tp + k * 10;
            wAmmoType.add(w.b.get(o)); wDmg.add(w.u16(o + 1)); wCone.add(w.u16(o + 3));
            wCd.add(w.b.get(o + 5)); wPerShot.add(w.b.get(o + 6)); wFlashTh.add(w.b.get(o + 7)); wSfx.add(w.u16(o + 8));
        }
    }
    /** municao da arma por tipo: 0 balas, 1 cartuchos, 2 foguetes, 3 celulas */
    Integer ammoOf(Integer atype) {
        if (atype == 1) return shells;
        if (atype == 2) return rockets;
        if (atype == 3) return cells;
        return bullets;
    }
    void spendAmmo(Integer atype, Integer n) {
        if (atype == 1) shells -= n;
        else if (atype == 2) rockets -= n;
        else if (atype == 3) cells -= n;
        else bullets -= n;
    }
    void parseGunLump(String nm) {
        Integer fp = w.findLump(nm).get(0);
        gunW.add(w.u16(fp));
        gunH.add(w.u16(fp + 2));
        gunPix.add(fp + 8);                   // pixels apos o header (w,h,lo,to)
    }
    void parseItems() {
        Integer fp = w.findLump('ITEMS').get(0);
        nitems = w.u16(fp);
        itX = new List<Integer>(); itY = new List<Integer>(); itSpr = new List<Integer>();
        itCat = new List<Integer>(); itAmt = new List<Integer>(); itGot = new List<Integer>();
        for (Integer i = 0; i < nitems; i++) {
            Integer o = fp + 2 + i * 9;
            itX.add(w.s16(o)); itY.add(w.s16(o + 2)); itSpr.add(w.u16(o + 4));
            itCat.add(w.b.get(o + 6)); itAmt.add(w.s16(o + 7)); itGot.add(0);
        }
    }
    void parseItemSprites() {
        isW = new List<Integer>(); isH = new List<Integer>(); isPix = new List<Integer>();
        Integer j = 0;
        while (true) {
            List<Integer> L = w.findLump('ISPR' + j);
            if (L == null) break;
            Integer fp = L.get(0);
            isW.add(w.u16(fp)); isH.add(w.u16(fp + 2)); isPix.add(fp + 8);
            j += 1;
        }
    }

    /** geometria vetorial de TODAS as linhas (ponto inicial, vetor e comprimento) */
    void buildLineGeom() {
        lax = new List<Integer>(); lay = new List<Integer>();
        lex = new List<Integer>(); ley = new List<Integer>(); lLen = new List<Integer>();
        for (Integer i = 0; i < w.lv1.size(); i++) {
            Integer a = w.lv1.get(i); Integer b = w.lv2.get(i);
            Integer ax = w.vx.get(a); Integer ay = w.vy.get(a);
            Integer ex = w.vx.get(b) - ax; Integer ey = w.vy.get(b) - ay;
            lax.add(ax); lay.add(ay); lex.add(ex); ley.add(ey);
            lLen.add(isqrt(ex * ex + ey * ey));
        }
        nlines = lax.size();
    }

    void parseHdr() {
        Integer fp = w.findLump('HDR').get(0);
        eyeBaseFloor = w.s16(fp);
        skyTexIdx = w.u16(fp + 2);
    }
    /** setores: floorH, ceilH, luz, indices de flat (chao/teto), flag de ceu */
    void parseSect() {
        List<Integer> L = w.findLump('SECT');
        Integer fp = L.get(0); Integer n = w.u16(fp); Integer base = fp + 2;
        secFloor = new List<Integer>(); secCeil = new List<Integer>(); secLight = new List<Integer>();
        secFloorFlat = new List<Integer>(); secCeilFlat = new List<Integer>(); secSky = new List<Integer>();
        secOpenCeil = new List<Integer>(); secDoor = new List<Integer>(); secDoorT = new List<Integer>();
        for (Integer si = 0; si < n; si++) {
            Integer o = base + si * 12;
            secFloor.add(w.s16(o)); secCeil.add(w.s16(o + 2));
            secLight.add(w.b.get(o + 4));
            secFloorFlat.add(w.u16(o + 5)); secCeilFlat.add(w.u16(o + 7));
            secSky.add(w.b.get(o + 9));
            secOpenCeil.add(w.s16(o + 10));
            secDoor.add(0); secDoorT.add(0);
        }
    }
    /** linedefs: setor front/back (-1 = sem back) + texturas e xoffset por lado */
    void parseLine() {
        List<Integer> L = w.findLump('LINE');
        Integer fp = L.get(0); Integer n = L.get(1) / 22;
        lFrontSec = new List<Integer>(); lBackSec = new List<Integer>();
        lfUp = new List<Integer>(); lfMid = new List<Integer>(); lfLo = new List<Integer>();
        lbUp = new List<Integer>(); lbMid = new List<Integer>(); lbLo = new List<Integer>();
        lfX = new List<Integer>(); lbX = new List<Integer>(); lDoor = new List<Integer>();
        for (Integer i = 0; i < n; i++) {
            Integer o = fp + i * 22;
            lFrontSec.add(w.s16(o)); lBackSec.add(w.s16(o + 2));
            lfUp.add(w.u16(o + 4)); lfMid.add(w.u16(o + 6)); lfLo.add(w.u16(o + 8));
            lbUp.add(w.u16(o + 10)); lbMid.add(w.u16(o + 12)); lbLo.add(w.u16(o + 14));
            lfX.add(w.s16(o + 16)); lbX.add(w.s16(o + 18)); lDoor.add(w.u16(o + 20));
        }
    }
    /** specials de gameplay por linha: acao (0 nada/1 lift/2 floor/3 exit), trigger (0 walk/1 use), tag */
    void parseLact() {
        List<Integer> L = w.findLump('LACT');
        Integer fp = L.get(0); Integer n = L.get(1) / 4;
        lAct = new List<Integer>(); lTrig = new List<Integer>(); lTag = new List<Integer>();
        for (Integer i = 0; i < n; i++) {
            Integer o = fp + i * 4;
            lAct.add(w.b.get(o)); lTrig.add(w.b.get(o + 1)); lTag.add(w.u16(o + 2));
        }
        List<Integer> LK = w.findLump('LKEY');           // cor de chave exigida por linha (0 = livre)
        lKey = new List<Integer>();
        Integer kfp = LK.get(0);
        for (Integer i = 0; i < n; i++) lKey.add(w.b.get(kfp + i));
    }
    /** por setor: tag + menor floor vizinho (alvo do lift) + estado da plataforma */
    void parseStag() {
        List<Integer> L = w.findLump('STAG');
        Integer fp = L.get(0); Integer n = L.get(1) / 4;
        secTag = new List<Integer>(); secLowFloor = new List<Integer>();
        secPlat = new List<Integer>(); secPlatT = new List<Integer>(); secPlatHigh = new List<Integer>();
        for (Integer i = 0; i < n; i++) {
            Integer o = fp + i * 4;
            secTag.add(w.u16(o)); secLowFloor.add(w.s16(o + 2));
            secPlat.add(0); secPlatT.add(0); secPlatHigh.add(secFloor.get(i));   // high = floor original
        }
    }
    void parseFlats() { flatFp = w.findLump('FLATPIX').get(0); }
    void parseSecGrid() {
        List<Integer> L = w.findLump('SECGRID');
        Integer fp = L.get(0);
        sgw = w.u16(fp); sgh = w.u16(fp + 2);
        secGrid = new List<Integer>();
        Integer base = fp + 4; Integer n = sgw * sgh;
        for (Integer k = 0; k < n; k++) secGrid.add(w.b.get(base + k));
    }
    /** setor que contem (x,y) pelo grid do BSP, ou -1 fora do mapa */
    Integer sectorAt(Integer x, Integer y) {
        Integer cx = cellX(x); Integer cy = cellY(y);
        if (cx < 0 || cx >= sgw || cy < 0 || cy >= sgh) return -1;
        Integer sv = secGrid.get(cy * sgw + cx);
        return (sv >= 254) ? -1 : sv;
    }
    /** colisao: bloqueia parede solida, void, vao baixo (porta fechada) e degrau alto */
    Boolean canMove(Integer fx, Integer fy, Integer tx, Integer ty) {
        if (isWall(tx, ty)) return false;
        Integer ts = sectorAt(tx, ty);
        if (ts < 0) return false;
        if (secCeil.get(ts) - secFloor.get(ts) < 56) return false;       // nao cabe (porta/baixo)
        Integer fs = sectorAt(fx, fy);
        if (fs >= 0 && secFloor.get(ts) - secFloor.get(fs) > 24) return false;   // degrau > 24
        return true;
    }

    void parsePalette() {
        Integer fp = w.findLump('PAL0').get(0);
        pal = new List<Integer>();
        for (Integer i = 0; i < 256; i++) {
            Integer o = fp + i * 3;
            pal.add(rgb(w.b.get(o), w.b.get(o + 1), w.b.get(o + 2)));
        }
    }
    void parseTextures() {
        Integer mfp = w.findLump('TEXMETA').get(0);
        Integer k = w.u16(mfp);
        tW = new List<Integer>(); tH = new List<Integer>(); tOff = new List<Integer>();
        for (Integer t = 0; t < k; t++) {
            Integer base = mfp + 2 + t * 8;
            tW.add(w.u16(base));
            tH.add(w.u16(base + 2));
            tOff.add(w.u32(base + 4));
        }
        texpixFp = w.findLump('TEXPIX').get(0);
    }

    /** raiz quadrada inteira (Newton), entrada ate ~5e7 */
    Integer isqrt(Integer v) {
        if (v < 2) return (v <= 0) ? 0 : 1;
        Integer x = 4096;
        for (Integer i = 0; i < 28; i++) x = (x + v / x) / 2;
        return x;
    }

    /** cmd (bitmask): 1=frente 2=tras 4=vira-esq 8=vira-dir 16=strafe-esq 32=strafe-dir.
     *  aplica movimento (com colisao deslizante) e retorna o frame RGB. */
    public List<Integer> stepFrame(Integer cmd) {
        prevX = gpx; prevY = gpy;                       // p/ detectar cruzamento de linha (walk-trigger)
        Integer turn = 0;
        if (Math.mod(cmd / 4, 2) == 1) turn += TURNV;
        if (Math.mod(cmd / 8, 2) == 1) turn -= TURNV;
        gang = pmod(gang + turn, 1024);

        Integer fwd = 0; Integer strafe = 0;
        if (Math.mod(cmd, 2) == 1) fwd += MOVEV;
        if (Math.mod(cmd / 2, 2) == 1) fwd -= MOVEV;
        if (Math.mod(cmd / 16, 2) == 1) strafe -= MOVEV;
        if (Math.mod(cmd / 32, 2) == 1) strafe += MOVEV;
        if (fwd != 0 || strafe != 0) {
            Integer dx = (cosT(gang) * fwd + cosT(gang - 256) * strafe) / S;
            Integer dy = (sinT(gang) * fwd + sinT(gang - 256) * strafe) / S;
            if (canMove(gpx, gpy, gpx + dx, gpy)) gpx += dx;   // desliza na parede/degrau
            if (canMove(gpx, gpy, gpx, gpy + dy)) gpy += dy;
        }
        checkCross();                                   // pisou em linha walk-trigger? (lift/floor)
        // olho acompanha o chao do setor atual (degraus sobem/descem a camera)
        playerSec = sectorAt(gpx, gpy);
        if (playerSec >= 0) {
            Integer tgt = secFloor.get(playerSec) + 41;
            Integer diff = tgt - eyeZ;
            if (diff > -3 && diff < 3) eyeZ = tgt; else eyeZ += diff / 3;
        }
        Boolean useNow = Math.mod(cmd / 256, 2) == 1;   // SPACE: abrir porta na mira (so na transicao)
        if (useNow && !useHeld) tryUse();
        useHeld = useNow;
        updateDoors();                                  // anima portas
        updateLifts();                                  // anima plataformas/lifts e floors
        // troca de arma (teclas 2..7): so equipa se ja possui
        if (Math.mod(cmd / 512, 2) == 1) curWeap = 2;
        if (Math.mod(cmd / 1024, 2) == 1 && ownWeap.get(3) == 1) curWeap = 3;
        if (Math.mod(cmd / 2048, 2) == 1 && ownWeap.get(4) == 1) curWeap = 4;
        if (Math.mod(cmd / 4096, 2) == 1 && ownWeap.get(5) == 1) curWeap = 5;
        if (Math.mod(cmd / 8192, 2) == 1 && ownWeap.get(6) == 1) curWeap = 6;
        if (Math.mod(cmd / 16384, 2) == 1 && ownWeap.get(7) == 1) curWeap = 7;
        // tiro: bit 64, consome a municao da arma atual (tabela WTAB)
        Integer wi = curWeap - 2;
        Integer atype = wAmmoType.get(wi);
        Boolean firing = (Math.mod(cmd / 64, 2) == 1 && fireTimer == 0 && ammoOf(atype) >= wPerShot.get(wi));
        if (firing) {
            spendAmmo(atype, wPerShot.get(wi));
            fireTimer = wCd.get(wi);
            playSfx(wSfx.get(wi), 255);
        }

        updateEnemies();         // acorda/persegue/ataca + animacao de morte
        updateProjectiles();     // move as bolas de fogo dos imps
        pickupItems();           // pega itens proximos (armas/municao/vida/armadura)
        renderRGB();             // paredes (preenche zbuf)
        if (firing) doHitscan(wDmg.get(wi), wCone.get(wi));   // dano/cone da arma atual
        renderEnemies();         // billboards com oclusao por zbuf
        renderProjectiles();     // bolas de fogo dos imps
        renderItems();           // itens como billboards
        drawGun();               // arma acima da barra de HUD
        if (flashT > 0) applyFlash();
        drawHud();               // barra: vida / rosto / municao
        if (Math.mod(cmd / 128, 2) == 1) drawAutomap();   // TAB: mapa do E1M1 por cima
        if (fireTimer > 0) fireTimer -= 1;
        if (flashT > 0) flashT -= 1;
        if (invT > 0) invT -= 1;
        if (hp <= 0) { playSfx(sfxDeath, 255); respawn(); }
        if (exitT > 0) { applyExitFlash(); exitT -= 1; if (exitT == 0) nextMap(); }   // saida -> proximo mapa
        return fb;
    }

    void respawn() {
        gpx = spawnX; gpy = spawnY; gang = spawnAng;
        prevX = gpx; prevY = gpy;
        hp = 100; bullets = 50; shells = 0; rockets = 0; cells = 0; curWeap = 2; flashT = 0; invT = 90;
        for (Integer k = 2; k < 8; k++) ownWeap.set(k, 0);
        ownWeap.set(2, 1);                                  // morte -> volta so com a pistola
    }

    /** pega itens proximos: aplica o efeito por categoria (dado do gerador, logica generica) */
    void pickupItems() {
        for (Integer i = 0; i < nitems; i++) {
            if (itGot.get(i) == 1) continue;
            Integer rx = gpx - itX.get(i); Integer ry = gpy - itY.get(i);
            if (rx * rx + ry * ry > 40 * 40) continue;       // raio de coleta
            Integer cat = itCat.get(i); Integer amt = itAmt.get(i);
            if (cat == 0) bullets = Math.min(bullets + amt, MAXBUL);
            else if (cat == 1) shells = Math.min(shells + amt, MAXSHL);
            else if (cat == 2) { if (hp < 100) hp = Math.min(hp + amt, 100); else continue; }
            else if (cat == 3) hp = Math.min(hp + amt, 200);
            else if (cat == 4) { if (armor < amt) armor = amt; else continue; }
            else if (cat == 5) armor = Math.min(armor + amt, 200);
            else if (cat == 6) {                                     // arma: equipa + municao inicial
                ownWeap.set(amt, 1); curWeap = amt;
                Integer at = wAmmoType.get(amt - 2);
                if (at == 0) bullets = Math.min(bullets + 10, MAXBUL);
                else if (at == 1) shells = Math.min(shells + 8, MAXSHL);
                else if (at == 2) rockets = Math.min(rockets + 2, MAXROK);
                else cells = Math.min(cells + 40, MAXCEL);
            }
            else if (cat == 7) hasKey.set(Math.mod(amt - 1, 3), 1);   // chave: cor = (id-1) mod 3
            else if (cat == 8) rockets = Math.min(rockets + amt, MAXROK);
            else if (cat == 9) cells = Math.min(cells + amt, MAXCEL);
            playSfx((cat == 6) ? sfxWeapon : sfxItem, 255);
            itGot.set(i, 1);
        }
    }

    /** cria um item no chao (drop de monstro): reusa o sprite de um item igual do mapa */
    void dropItem(Integer x, Integer y, Integer cat, Integer amt) {
        Integer spr = -1;
        for (Integer i = 0; i < nitems; i++) {
            if (itCat.get(i) == cat && itAmt.get(i) == amt) { spr = itSpr.get(i); break; }
        }
        if (spr < 0) for (Integer i = 0; i < nitems; i++) if (itCat.get(i) == cat) { spr = itSpr.get(i); break; }
        if (spr < 0) return;                              // mapa nao tem sprite desse tipo -> sem drop
        itX.add(x); itY.add(y); itSpr.add(spr); itCat.add(cat); itAmt.add(amt); itGot.add(0);
        nitems += 1;
    }

    /** itens como billboards (sprite no chao do setor), com oclusao por zbuf */
    void renderItems() {
        Integer dirX = cosT(gang); Integer dirY = sinT(gang);
        for (Integer i = 0; i < nitems; i++) {
            if (itGot.get(i) == 1) continue;
            Integer rx = itX.get(i) - gpx; Integer ry = itY.get(i) - gpy;
            Integer depth = (rx * dirX + ry * dirY) / S;
            if (depth < 16) continue;
            Integer side = (rx * dirY - ry * dirX) / S;
            Integer screenCol = VW / 2 + side * projS / depth;
            Integer spr = itSpr.get(i);
            Integer sw = isW.get(spr); Integer sh = isH.get(spr); Integer pixfp = isPix.get(spr);
            Integer ssH = sh * projS / depth; if (ssH < 1) continue;
            Integer ssW = ssH * sw / sh;
            Integer floorH = spriteFloor(itX.get(i), itY.get(i));
            Integer baseRow = horiz + (eyeZ - floorH) * projS / depth;
            if (baseRow > VH) baseRow = VH;
            Integer top = baseRow - ssH; Integer left = screenCol - ssW / 2;
            Integer shade = 280 - depth / 5; if (shade < 60) shade = 60; if (shade > 256) shade = 256;
            blitBillboard(sw, sh, pixfp, ssW, ssH, left, top, depth, shade);
        }
    }
    /** altura do chao no ponto (x,y) pelo grid de setores (itens/monstros pisam certo) */
    Integer spriteFloor(Integer x, Integer y) {
        Integer sec = sectorAt(x, y);
        return (sec >= 0) ? secFloor.get(sec) : eyeBaseFloor;
    }
    /** blita um billboard escalado com oclusao por zbuf + sombra (compartilhado itens/monstros) */
    void blitBillboard(Integer sw, Integer sh, Integer pixfp, Integer ssW, Integer ssH,
                       Integer left, Integer top, Integer depth, Integer shade) {
        Integer dx0 = (left < 0) ? -left : 0;
        Integer dx1 = (left + ssW > VW) ? VW - left : ssW;
        Integer dy0 = (top < 0) ? -top : 0;
        Integer dy1 = (top + ssH > VH) ? VH - top : ssH;
        for (Integer dx = dx0; dx < dx1; dx++) {
            Integer cx = left + dx;
            if (depth >= zbuf.get(cx)) continue;
            Integer texX = dx * sw / ssW;
            Integer colBase = pixfp + texX * sh;
            for (Integer dy = dy0; dy < dy1; dy++) {
                Integer pidx = w.b.get(colBase + dy * sh / ssH);
                if (pidx == 255) continue;
                Integer base = pal.get(pidx);
                fb.set(cx + (top + dy) * VW, rgb((base / 65536) * shade / 256,
                    Math.mod(base / 256, 256) * shade / 256, Math.mod(base, 256) * shade / 256));
            }
        }
    }

    /** USE (SPACE): acha a porta na mira (raio central curto) e aciona o setor de tras */
    void tryUse() {
        Integer rdx = cosT(gang) / 256; Integer rdy = sinT(gang) / 256;
        Integer bestD = 999999; Integer bestLine = -1;
        for (Integer i = 0; i < nlines; i++) {
            Boolean isDoor = lDoor.get(i) == 1;
            Boolean isSwitch = lTrig.get(i) == 1 && lAct.get(i) > 0;   // alavanca/botao (USE)
            if (!isDoor && !isSwitch) continue;
            Integer ex = lex.get(i); Integer ey = ley.get(i);
            Integer den = rdx * ey - rdy * ex; if (den == 0) continue;
            Integer ax = lax.get(i) - gpx; Integer ay = lay.get(i) - gpy;
            Integer tnum = ax * ey - ay * ex; Integer snum = ax * rdy - ay * rdx;
            Boolean ok;
            if (den > 0) ok = (tnum >= 0) && (snum >= 0) && (snum <= den);
            else ok = (tnum <= 0) && (snum <= 0) && (snum >= den);
            if (!ok) continue;
            Integer ddx = rdx * tnum / den; Integer ddy = rdy * tnum / den;
            Integer dist = isqrt(ddx * ddx + ddy * ddy);
            if (dist < bestD) { bestD = dist; bestLine = i; }
        }
        if (bestLine < 0 || bestD > 96) return;            // alcance do USE
        if (lTrig.get(bestLine) == 1 && lAct.get(bestLine) > 0) {   // alavanca: exit / lift remoto
            triggerAction(bestLine); playSfx(sfxDoorOpen, 255); return;
        }
        Integer fsec = lFrontSec.get(bestLine); Integer bsec = lBackSec.get(bestLine);
        Integer door = (fsec == playerSec) ? bsec : fsec;  // setor do outro lado
        if (door < 0) door = bsec;
        if (door < 0) return;
        Integer needKey = lKey.get(bestLine);                                   // porta trancada?
        if (needKey > 0 && hasKey.get(needKey - 1) == 0) { playSfx(sfxNoWay, 255); return; }
        Integer st = secDoor.get(door);
        if (st == 0) { secDoor.set(door, 1); playSfx(sfxDoorOpen, 255); }       // fechada -> abre
        else if (st == 2) { secDoor.set(door, 3); playSfx(sfxDoorClose, 255); } // aberta -> fecha
    }

    /** anima portas: sobe o teto ate openCeil, espera, desce (reabre se o player esta embaixo) */
    void updateDoors() {
        for (Integer di = 0; di < secDoor.size(); di++) {
            Integer st = secDoor.get(di);
            if (st == 0) continue;
            if (st == 1) {                                  // abrindo
                Integer c = secCeil.get(di) + 8;
                Integer tgt = secOpenCeil.get(di);
                if (c >= tgt) { secCeil.set(di, tgt); secDoor.set(di, 2); secDoorT.set(di, 140); }
                else secCeil.set(di, c);
            } else if (st == 2) {                           // aberta esperando
                Integer t = secDoorT.get(di) - 1;
                if (t <= 0) secDoor.set(di, 3); else secDoorT.set(di, t);
            } else {                                        // fechando
                if (di == playerSec) { secDoor.set(di, 1); continue; }   // nao esmaga o player
                Integer c = secCeil.get(di) - 8;
                if (c <= secFloor.get(di)) { secCeil.set(di, secFloor.get(di)); secDoor.set(di, 0); }
                else secCeil.set(di, c);
            }
        }
    }

    /** sinal do produto vetorial: orientacao de C em relacao ao segmento A->B */
    Integer orient(Integer ax, Integer ay, Integer bx, Integer by, Integer cx, Integer cy) {
        return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    }
    /** os segmentos AB e CD se cruzam? (interseccao propria por sinais de orientacao) */
    Boolean segCross(Integer ax, Integer ay, Integer bx, Integer by,
                     Integer cx, Integer cy, Integer ex, Integer ey) {
        Integer d1 = orient(cx, cy, ex, ey, ax, ay);
        Integer d2 = orient(cx, cy, ex, ey, bx, by);
        Integer d3 = orient(ax, ay, bx, by, cx, cy);
        Integer d4 = orient(ax, ay, bx, by, ex, ey);
        Boolean ab = (d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0);
        Boolean cd = (d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0);
        return ab && cd;
    }
    /** cruzou alguma linha walk-trigger neste frame? dispara a acao (lift/floor) */
    void checkCross() {
        if (prevX == gpx && prevY == gpy) return;
        for (Integer i = 0; i < nlines; i++) {
            if (lAct.get(i) == 0 || lTrig.get(i) != 0) continue;     // so walk-trigger com acao
            if (segCross(prevX, prevY, gpx, gpy,
                         lax.get(i), lay.get(i), lax.get(i) + lex.get(i), lay.get(i) + ley.get(i))) {
                triggerAction(i);
            }
        }
    }
    /** dispara a acao de uma linha: exit (flash) ou lift/floor nos setores com a tag */
    void triggerAction(Integer i) {
        Integer act = lAct.get(i); Integer tag = lTag.get(i);
        if (act == 3) { if (exitT == 0) exitT = 60; return; }        // saida do nivel
        for (Integer sx = 0; sx < secPlat.size(); sx++) {           // 'sx': 's' colidiria com a constante S
            if (secTag.get(sx) != tag || secPlat.get(sx) != 0) continue;
            if (act == 1) secPlat.set(sx, 1);                        // lift: desce-espera-sobe
            else if (act == 2) secPlat.set(sx, 4);                   // floor: desce e fica
        }
    }
    /** anima plataformas: lift (desce/espera/sobe) e floor-lower (desce e para) */
    void updateLifts() {
        for (Integer sx = 0; sx < secPlat.size(); sx++) {            // 'sx': 's' colidiria com a constante S
            Integer st = secPlat.get(sx);
            if (st == 0) continue;
            if (st == 1) {                                            // lift descendo
                Integer f = secFloor.get(sx) - 8;
                if (f <= secLowFloor.get(sx)) { secFloor.set(sx, secLowFloor.get(sx)); secPlat.set(sx, 2); secPlatT.set(sx, 105); }
                else secFloor.set(sx, f);
            } else if (st == 2) {                                     // esperando embaixo
                Integer t = secPlatT.get(sx) - 1;
                if (t <= 0) secPlat.set(sx, 3); else secPlatT.set(sx, t);
            } else if (st == 3) {                                     // subindo de volta
                Integer f = secFloor.get(sx) + 8;
                if (f >= secPlatHigh.get(sx)) { secFloor.set(sx, secPlatHigh.get(sx)); secPlat.set(sx, 0); }
                else secFloor.set(sx, f);
            } else {                                                  // st==4: floor-lower (desce e para)
                Integer f = secFloor.get(sx) - 8;
                if (f <= secLowFloor.get(sx)) { secFloor.set(sx, secLowFloor.get(sx)); secPlat.set(sx, 0); }
                else secFloor.set(sx, f);
            }
        }
    }

    /** atualiza monstros: acorda com LOS, persegue, ataca (errando as vezes); anima a queda */
    void updateEnemies() {
        tick += 1;
        for (Integer i = 0; i < nent; i++) {
            if (enAtkT.get(i) > 0) enAtkT.set(i, enAtkT.get(i) - 1);   // pose de ataque some
            Integer st = enState.get(i);
            if (st == 1) {                              // morrendo: avanca a animacao de queda
                Integer t = enDT.get(i) - 1;
                if (t <= 0) {
                    Integer fr = enDF.get(i) + 1;
                    if (fr >= 4) { enDF.set(i, 4); enState.set(i, 2); }   // assenta como corpo
                    else { enDF.set(i, fr); enDT.set(i, DTICKS); }
                } else enDT.set(i, t);
                continue;
            }
            if (st != 0) continue;                      // corpo: parado
            Integer rx = gpx - enX.get(i); Integer ry = gpy - enY.get(i);
            Integer d = isqrt(rx * rx + ry * ry);

            // dormindo: so acorda se VER o jogador de perto (igual DOOM, nao acorda o mapa todo)
            if (enWake.get(i) == 0) {
                if (d < WAKEDIST && hasLOS(enX.get(i), enY.get(i), gpx, gpy)) {
                    enWake.set(i, 1);
                    enAtk.set(i, Math.mod(i * 13, ATKCD));   // nao ataca no mesmo instante que acorda
                    playSfx(monSight.get(enCls.get(i)), sfxVolDist(d));
                } else continue;                         // continua dormindo (nao move/ataca)
            }

            // facing acompanha o player com lag (lerp + normaliza) -> mostra os lados ao circular
            Integer dd = (d < 1) ? 1 : d;
            Integer nfx = (enFx.get(i) * 7 + rx * S / dd) / 8;
            Integer nfy = (enFy.get(i) * 7 + ry * S / dd) / 8;
            Integer lfn = isqrt(nfx * nfx + nfy * nfy); if (lfn < 1) lfn = 1;
            enFx.set(i, nfx * S / lfn); enFy.set(i, nfy * S / lfn);

            if (d > 90) {                                // persegue
                Integer nx = enX.get(i) + rx * ENSPD / d;
                Integer ny = enY.get(i) + ry * ENSPD / d;
                if (!isWall(nx, enY.get(i))) enX.set(i, nx);
                if (!isWall(enX.get(i), ny)) enY.set(i, ny);
            }

            Integer cd = enAtk.get(i);
            if (cd > 0) { enAtk.set(i, cd - 1); continue; }
            if (d < ATKRANGE && hasLOS(enX.get(i), enY.get(i), gpx, gpy)) {
                enAtk.set(i, ATKCD);                     // cadencia (mesmo errando)
                enAtkT.set(i, 12);                       // mostra a pose de ataque
                playSfx(monAtk.get(enCls.get(i)), sfxVolDist(d));
                if (enCls.get(i) == 2) {
                    spawnFireball(i);                    // imp: bola de fogo (voa e da dano ao acertar)
                } else {
                    Boolean hits = Math.mod(tick + i * 7, 100) < 52;     // hitscan ~52% acerta
                    if (hits && invT == 0) {
                        hp -= 3 + enCls.get(i) * 2;      // zombie 3, shotgun 5
                        flashT = 6;
                        if (hp > 0) playSfx(sfxPain, 255);   // morte toca o som de morte (no stepFrame)
                    }
                }
            }
        }
    }

    /** linha de visao: marcha de (x0,y0) a (x1,y1); falso se bater em parede
     *  ou em vao baixo (porta fechada) antes — visao nao atravessa porta. */
    Boolean hasLOS(Integer x0, Integer y0, Integer x1, Integer y1) {
        Integer dx = x1 - x0; Integer dy = y1 - y0;
        Integer dist = isqrt(dx * dx + dy * dy);
        Integer steps = dist / 24;
        if (steps < 1) return true;
        for (Integer ls = 1; ls < steps; ls++) {   // 'ls': contador 's' colide com a constante S no for
            Integer lx = x0 + dx * ls / steps; Integer ly = y0 + dy * ls / steps;
            if (isWall(lx, ly)) return false;
            Integer sct = sectorAt(lx, ly);
            if (sct >= 0 && secCeil.get(sct) - secFloor.get(sct) < 56) return false;   // porta fechada/vao baixo
        }
        return true;
    }

    /** hitscan no raio central: dano no monstro vivo mais proximo na mira (antes da parede) */
    void doHitscan(Integer dmg, Integer cone) {
        Integer dirX = cosT(gang); Integer dirY = sinT(gang);
        Integer bestDepth = MAXD;
        Integer best = -1;
        for (Integer i = 0; i < nent; i++) {
            if (enState.get(i) != 0) continue;
            Integer rx = enX.get(i) - gpx; Integer ry = enY.get(i) - gpy;
            Integer depth = (rx * dirX + ry * dirY) / S;
            if (depth <= 0) continue;
            Integer side = (rx * dirY - ry * dirX) / S;  // dist perpendicular ao raio (world)
            if (Math.abs(side) > cone) continue;         // largura do feixe (cone)
            Integer scol = VW / 2 + side * projS / depth;          // coluna do alvo na tela
            if (scol < 0) scol = 0; if (scol > VW - 1) scol = VW - 1;
            if (depth >= zbuf.get(scol)) continue;       // parede na frente DESSA coluna -> bloqueia
            if (depth < bestDepth) { bestDepth = depth; best = i; }
        }
        if (best >= 0) {
            enHP.set(best, enHP.get(best) - dmg);
            Integer cls = enCls.get(best);
            if (enHP.get(best) <= 0) {
                enState.set(best, 1); enDF.set(best, 0); enDT.set(best, DTICKS);
                playSfx(monDeath.get(cls), sfxVolDist(bestDepth));
                if (enDropC.get(best) != 255) dropItem(enX.get(best), enY.get(best), enDropC.get(best), enDropA.get(best));
            } else {
                playSfx(monPain.get(cls), sfxVolDist(bestDepth));
            }
        }
    }

    /** renderiza os monstros como billboards: ordena longe->perto, oclui pelo zbuf */
    void renderEnemies() {
        Integer dirX = cosT(gang); Integer dirY = sinT(gang);
        List<Integer> order = new List<Integer>();
        List<Integer> dep = new List<Integer>();
        for (Integer i = 0; i < nent; i++) {
            Integer rx = enX.get(i) - gpx; Integer ry = enY.get(i) - gpy;
            order.add(i); dep.add((rx * dirX + ry * dirY) / S);
        }
        for (Integer a = 0; a < order.size(); a++) {     // selection sort por profundidade desc
            Integer mx = a;
            for (Integer b = a + 1; b < order.size(); b++) if (dep.get(b) > dep.get(mx)) mx = b;
            if (mx != a) {
                Integer t = order.get(a); order.set(a, order.get(mx)); order.set(mx, t);
                Integer td = dep.get(a); dep.set(a, dep.get(mx)); dep.set(mx, td);
            }
        }
        for (Integer oi = 0; oi < order.size(); oi++) {
            Integer i = order.get(oi);
            Integer depth = dep.get(oi);
            if (depth < 16) continue;                    // atras/colado
            Integer rx = enX.get(i) - gpx; Integer ry = enY.get(i) - gpy;
            Integer side = (rx * dirY - ry * dirX) / S;
            Integer screenCol = VW / 2 + side * projS / depth;
            Integer cls = enCls.get(i);
            Integer sw; Integer sh; Integer pixfp; Integer mir = 0;
            if (enState.get(i) == 0) {                   // vivo: ataque (frontal) > caminhada > parado
                if (enAtkT.get(i) > 0) { sw = monKW.get(cls); sh = monKH.get(cls); pixfp = monKPix.get(cls); }
                else {                                   // idle/walk: escolhe 1 das 8 vistas
                    Integer ridx = spriteRot(i);
                    Integer phys = rotPhys.get(ridx); mir = rotMir.get(ridx);
                    Integer si = cls * 5 + phys;
                    if (enWake.get(i) == 1 && Math.mod(tick / 6, 2) == 1) { sw = walkW.get(si); sh = walkH.get(si); pixfp = walkPix.get(si); }
                    else { sw = idleW.get(si); sh = idleH.get(si); pixfp = idlePix.get(si); }
                }
            } else {                                      // morrendo/corpo: frame da queda
                Integer di = cls * 5 + enDF.get(i);
                sw = monDW.get(di); sh = monDH.get(di); pixfp = monDPix.get(di);
            }
            Integer ssH = sh * projS / depth;             // altura do sprite (unidades de mapa)
            if (ssH < 1) continue;
            Integer ssW = ssH * sw / sh;
            Integer floorH = spriteFloor(enX.get(i), enY.get(i));
            Integer baseRow = horiz + (eyeZ - floorH) * projS / depth;   // pe no chao do setor do monstro
            if (baseRow > VH) baseRow = VH;
            Integer top = baseRow - ssH;
            Integer left = screenCol - ssW / 2;
            Integer shade = 280 - depth / 5;
            if (shade < 55) shade = 55; if (shade > 256) shade = 256;
            Integer dx0 = (left < 0) ? -left : 0;
            Integer dx1 = (left + ssW > VW) ? VW - left : ssW;
            Integer dy0 = (top < 0) ? -top : 0;
            Integer dy1 = (top + ssH > VH) ? VH - top : ssH;
            for (Integer dx = dx0; dx < dx1; dx++) {
                Integer cx = left + dx;
                if (depth >= zbuf.get(cx)) continue;     // ocluso por parede
                Integer texX = (mir == 1) ? (sw - 1 - dx * sw / ssW) : (dx * sw / ssW);
                Integer colBase = pixfp + texX * sh;
                for (Integer dy = dy0; dy < dy1; dy++) {
                    Integer pidx = w.b.get(colBase + dy * sh / ssH);
                    if (pidx == 255) continue;           // transparente
                    Integer base = pal.get(pidx);
                    Integer r = (base / 65536) * shade / 256;
                    Integer g = Math.mod(base / 256, 256) * shade / 256;
                    Integer bl = Math.mod(base, 256) * shade / 256;
                    fb.set(cx + (top + dy) * VW, rgb(r, g, bl));
                }
            }
        }
    }

    /** blita um sprite (col-major, 255=transparente) escalado, ancorado embaixo-centro */
    void blitSprite(Integer sw, Integer sh, Integer pixfp, Integer cx, Integer bottomY) {
        if (sw <= 0 || sh <= 0) return;
        Integer dw = sw * VW / 320; Integer dh = sh * VW / 320;
        if (dw < 1) dw = 1; if (dh < 1) dh = 1;
        Integer gx0 = cx - dw / 2;
        Integer gy0 = bottomY - dh;
        for (Integer dy = 0; dy < dh; dy++) {
            Integer py = gy0 + dy;
            if (py < 0 || py >= VH) continue;
            Integer sy = dy * sh / dh;
            for (Integer dx = 0; dx < dw; dx++) {
                Integer pxc = gx0 + dx;
                if (pxc < 0 || pxc >= VW) continue;
                Integer sx = dx * sw / dw;
                Integer pidx = w.b.get(pixfp + sx * sh + sy);
                if (pidx == 255) continue;       // transparente
                fb.set(pxc + py * VW, pal.get(pidx));
            }
        }
    }
    void drawGun() {
        Integer base = (curWeap - 2) * 3;                     // pistola=0, shotgun=3
        Integer fr = (fireTimer > 0) ? base + 1 : base;       // recuo enquanto dispara
        Integer gunBottom = VH - hudH;                        // arma acima da barra
        Integer flashTh = wFlashTh.get(curWeap - 2);          // clarao so nos primeiros frames
        if (fireTimer > flashTh) blitSprite(gunW.get(base + 2), gunH.get(base + 2), gunPix.get(base + 2), VW / 2, gunBottom - VH / 12);
        blitSprite(gunW.get(fr), gunH.get(fr), gunPix.get(fr), VW / 2, gunBottom);
    }

    /** blit escalado, ancorado no canto superior-esquerdo (HUD/digitos) */
    void blitAt(Integer sw, Integer sh, Integer pixfp, Integer dx0, Integer dy0, Integer num, Integer den) {
        Integer dw = sw * num / den; Integer dh = sh * num / den;
        if (dw < 1) dw = 1; if (dh < 1) dh = 1;
        for (Integer dy = 0; dy < dh; dy++) {
            Integer py = dy0 + dy;
            if (py < 0 || py >= VH) continue;
            Integer sy = dy * sh / dh;
            for (Integer dx = 0; dx < dw; dx++) {
                Integer px = dx0 + dx;
                if (px < 0 || px >= VW) continue;
                Integer pidx = w.b.get(pixfp + (dx * sw / dw) * sh + sy);
                if (pidx == 255) continue;
                fb.set(px + py * VW, pal.get(pidx));
            }
        }
    }
    /** numero alinhado a direita em rightX */
    void drawNumber(Integer val, Integer rightX, Integer y, Integer num, Integer den) {
        Integer v = (val < 0) ? 0 : val;
        Integer x = rightX;
        while (true) {
            Integer dig = Math.mod(v, 10);
            x -= numW.get(dig) * num / den;
            blitAt(numW.get(dig), numH.get(dig), numPix.get(dig), x, y, num, den);
            v = v / 10;
            if (v == 0) break;
        }
    }
    /** tinge a area 3D de vermelho ao tomar dano */
    void applyFlash() {
        Integer add = flashT * 8;
        Integer lim = VW * (VH - hudH);
        for (Integer i = 0; i < lim; i++) {
            Integer c = fb.get(i);
            Integer r = c / 65536 + add; if (r > 255) r = 255;
            fb.set(i, rgb(r, Math.mod(c / 256, 256), Math.mod(c, 256)));
        }
    }
    /** clarao de saida do nivel: fade-to-white (levemente dourado) ao acionar a alavanca */
    void applyExitFlash() {
        Integer add = (60 - exitT) * 4; if (add > 255) add = 255;
        Integer lim = VW * VH;
        for (Integer i = 0; i < lim; i++) {
            Integer c = fb.get(i);
            Integer r = c / 65536 + add; if (r > 255) r = 255;
            Integer g = Math.mod(c / 256, 256) + add; if (g > 255) g = 255;
            Integer b = Math.mod(c, 256) + add * 7 / 8; if (b > 255) b = 255;
            fb.set(i, rgb(r, g, b));
        }
    }
    /** barra de HUD: vida + % a esquerda, rosto no centro, municao a direita */
    void drawHud() {
        Integer num = VW; Integer den = 320;                       // STBAR e 320 de largura
        Integer barTop = VH - hudH;
        blitAt(sbW, sbH, sbPix, 0, barTop, num, den);              // fundo: barra de status real
        blitAt(saW, saH, saPix, 104 * num / den, barTop, num, den); // painel "ARMS" sobre o "FRAG"
        // armas: 2..7 na grade do ARMS; amarelo = tem, cinza = nao tem (so a pistola=2)
        for (Integer wi = 0; wi < 6; wi++) {
            Integer wn = wi + 2;
            Integer ax = (111 + Math.mod(wi, 3) * 12) * num / den;
            Integer ay = barTop + (4 + (wi / 3) * 10) * num / den;
            Boolean own = ownWeap.get(wn) == 1;
            if (own) blitAt(ynW.get(wn), ynH.get(wn), ynPix.get(wn), ax, ay, num, den);
            else blitAt(gnW.get(wn), gnH.get(wn), gnPix.get(wn), ax, ay, num, den);
        }
        // widgets nas coordenadas canonicas do DOOM (st_stuff.c), em coords da barra 320x32
        Integer y3 = barTop + 3 * num / den;
        Integer ammoNow = ammoOf(wAmmoType.get(curWeap - 2));     // municao do tipo da arma atual
        drawNumber(ammoNow, 44 * num / den, y3, num, den);        // municao da arma atual (right em x=44)
        drawNumber(hp, 88 * num / den, y3, num, den);             // vida (right em x=90)
        blitAt(pcW, pcH, pcPix, 88 * num / den, y3, num, den);    // '%'
        drawNumber(armor, 221 * num / den, y3, num, den);         // armadura (right em x=221)
        blitAt(pcW, pcH, pcPix, 221 * num / den, y3, num, den);   // '%'
        // rosto do Doomguy conforme a vida: bucket = (100-hp)*5/101 (igual ao DOOM)
        Integer fi = (100 - hp) * 5 / 101;
        if (fi < 0) fi = 0; if (fi > 4) fi = 4;
        Integer fw; Integer fh; Integer fpx;
        if (hp > 0) { fw = faW.get(fi); fh = faH.get(fi); fpx = faPix.get(fi); }
        else { fw = fdW; fh = fdH; fpx = fdPix; }
        blitAt(fw, fh, fpx, 143 * num / den, barTop + 1 * num / den, num, den);   // rosto (x=143)
    }

    Integer rgb(Integer r, Integer g, Integer b) { return r * 65536 + g * 256 + b; }

    /** self-test headless da API grafica (roda via allx, sem janela) */
    public static void gtest() {
        Doom d = new Doom();
        d.init(64, 40);
        List<Integer> f = d.stepFrame(1);          // 1 passo pra frente
        Integer nz = 0;
        for (Integer c : f) if (c > 0) nz++;
        System.debug('fb size=' + f.size() + ' (esperado 2560) nonzero=' + nz);
        System.debug('player apos step: ' + d.gpx + ',' + d.gpy + ' ang=' + d.gang);
        System.debug('pixel centro=' + f.get(20 * 64 + 32) + ' topo=' + f.get(32) + ' base=' + f.get(39 * 64 + 32));
        // audio: banco carregado + evento de disparo enfileirado
        List<Integer> bank = d.audioBank();
        Integer sfxN = (bank.size() > 1) ? bank.get(0) + bank.get(1) * 256 : 0;
        d.soundEvents();                            // drena o que veio do step(1)
        d.stepFrame(64);                            // dispara a pistola (bit 64)
        List<Integer> ev = d.soundEvents();
        System.debug('audioBank bytes=' + bank.size() + ' sfxN=' + sfxN + ' (esperado 18)');
        System.debug('soundEvents apos fire=' + ev.size() + ' id0=' + (ev.size() > 0 ? ev.get(0) : -1) +
                     ' vol0=' + (ev.size() > 1 ? ev.get(1) : -1) + ' (sfxPistol=' + d.sfxPistol + ')');
        // 8 angulos: rotacao escolhida p/ os primeiros monstros (deve cair em 0..7)
        String rs = '';
        for (Integer i = 0; i < d.nent && i < 6; i++) rs += d.spriteRot(i) + ' ';
        System.debug('spriteRot[0..5]= ' + rs + '| idleSprites=' + d.idleW.size() + ' (esperado 15)' +
                     ' rotPhys[5]=' + d.rotPhys.get(5) + ' rotMir[5]=' + d.rotMir.get(5) + ' (esperado 3,1)');
        // prova dos 8 octantes: facing fixo (leste), camera dando a volta no monstro
        d.enFx.set(0, S); d.enFy.set(0, 0);
        Integer mx = d.enX.get(0); Integer my = d.enY.get(0);
        String oct = '';
        for (Integer a = 0; a < 1024; a += 128) {
            d.gpx = mx + d.cosT(a) * 200 / S; d.gpy = my + d.sinT(a) * 200 / S;
            oct += d.spriteRot(0) + ' ';
        }
        System.debug('octantes (facing leste, camera 0..315 graus): ' + oct);
        // Onda B: specials de gameplay (lift/switch) carregados + cruzamento aciona o lift
        Integer nLift = 0; Integer nSwitch = 0; Integer liftLine = -1;
        for (Integer i = 0; i < d.nlines; i++) {
            if (d.lAct.get(i) == 1) { nLift++; if (liftLine < 0) liftLine = i; }
            if (d.lTrig.get(i) == 1 && d.lAct.get(i) > 0) nSwitch++;
        }
        System.debug('lAct=' + d.lAct.size() + ' secTag=' + d.secTag.size() + ' lifts=' + nLift + ' switches=' + nSwitch);
        if (liftLine >= 0) {
            Integer tag = d.lTag.get(liftLine);
            Integer lmx = d.lax.get(liftLine) + d.lex.get(liftLine) / 2;
            Integer lmy = d.lay.get(liftLine) + d.ley.get(liftLine) / 2;    // meio da linha do lift
            Integer nx = 0 - d.ley.get(liftLine); Integer ny = d.lex.get(liftLine);   // normal
            Integer ln = d.isqrt(nx * nx + ny * ny); if (ln < 1) ln = 1;
            d.prevX = lmx - nx * 40 / ln; d.prevY = lmy - ny * 40 / ln;
            d.gpx = lmx + nx * 40 / ln; d.gpy = lmy + ny * 40 / ln;         // cruza de um lado ao outro
            d.checkCross();
            Integer moving = 0; Integer haveTag = 0;
            for (Integer sx = 0; sx < d.secPlat.size(); sx++) {
                if (d.secTag.get(sx) == tag) haveTag++;
                if (d.secTag.get(sx) == tag && d.secPlat.get(sx) != 0) moving++;
            }
            System.debug('cruzou lift line=' + liftLine + ' tag=' + tag + ' setoresComTag=' + haveTag +
                         ' descendo=' + moving + ' (esperado 1, 1)');
        }
        // Onda C: projetil do imp — spawn manual no ponto de start (aberto), na direcao que o player olha
        d.prjLife.set(0, 110); d.prjX.set(0, d.spawnX); d.prjY.set(0, d.spawnY); d.prjZ.set(0, d.eyeZ);
        d.prjVx.set(0, d.cosT(d.spawnAng) * PROJSPD / S); d.prjVy.set(0, d.sinT(d.spawnAng) * PROJSPD / S);
        d.gpx = d.spawnX - d.cosT(d.spawnAng) * 600 / S; d.gpy = d.spawnY - d.sinT(d.spawnAng) * 600 / S;  // player atras
        Integer by0 = d.prjY.get(0);
        d.updateProjectiles(); d.updateProjectiles();
        System.debug('fireball: fbPix=' + d.fbPix + ' (>0=sprite ok) vivo=' + (d.prjLife.get(0) > 0) +
                     ' moveu pos ' + by0 + '->' + d.prjY.get(0));
        // spawnFireball cria projetil mirando o player
        for (Integer p = 0; p < MAXPROJ; p++) d.prjLife.set(p, 0);
        d.gpx = d.enX.get(0) + 400; d.gpy = d.enY.get(0);
        d.spawnFireball(0);
        Integer cnt = 0; for (Integer p = 0; p < MAXPROJ; p++) if (d.prjLife.get(p) > 0) cnt++;
        System.debug('spawnFireball -> projeteis ativos=' + cnt + ' (esperado 1)');
        // multi-mapa: transicao E1M1 -> E1M2 preservando o estado do player
        System.debug('mapCount=' + WadData.mapCount() + ' curMap=' + d.curMap + ' E1M1 nlines=' + d.nlines);
        d.hp = 55; d.shells = 17; d.ownWeap.set(3, 1);     // marca p/ checar persistencia
        d.nextMap();
        List<Integer> f2 = d.stepFrame(1);
        Integer nz2 = 0; for (Integer c : f2) if (c > 0) nz2++;
        System.debug('apos nextMap: curMap=' + d.curMap + ' E1M2 nlines=' + d.nlines + ' setores=' + d.secFloor.size() +
                     ' hp=' + d.hp + ' shells=' + d.shells + ' shotgun=' + d.ownWeap.get(3) + ' (persistiu 55/17/1)');
        // armas: tabela WTAB + munição por tipo + troca/tiro
        d.ownWeap.set(4, 1); d.bullets = 100;
        Integer wsprites = d.gunW.size();
        Integer cgDmg = d.wDmg.get(2); Integer cgCd = d.wCd.get(2); Integer cgType = d.wAmmoType.get(2);
        System.debug('armas: sprites=' + wsprites + ' (esperado 18) | chaingun dmg=' + cgDmg + ' cd=' + cgCd +
                     ' ammoType=' + cgType + ' | rocket dmg=' + d.wDmg.get(3) + ' ammoType=' + d.wAmmoType.get(3) +
                     ' | plasma ammoType=' + d.wAmmoType.get(4));
        System.debug('E1M2 render: fb nonzero=' + nz2 + ' player=' + d.gpx + ',' + d.gpy + ' (novo spawn)');
        // chaves: portas trancadas no E1M2 + hasKey
        Integer locked = 0; Integer kcolor = 0;
        for (Integer i = 0; i < d.nlines; i++) if (d.lKey.get(i) > 0) { locked++; kcolor = d.lKey.get(i); }
        System.debug('chaves: lKey=' + d.lKey.size() + ' sfxNoWay=' + d.sfxNoWay + ' hasKey=' + d.hasKey.size() +
                     ' portas trancadas E1M2=' + locked + ' (cor exemplo=' + kcolor + ')');
        // fix LOS: porta fechada bloqueia a visao (testa numa celula do setor da porta)
        Integer dsec = -1; Integer dcx = 0; Integer dcy = 0;
        for (Integer i = 0; i < d.nlines && dsec < 0; i++) {
            if (d.lDoor.get(i) != 1) continue;
            Integer bs = d.lBackSec.get(i);
            if (bs < 0) continue;
            if (d.secCeil.get(bs) - d.secFloor.get(bs) >= 56) continue;   // so porta FECHADA
            for (Integer gy = 0; gy < d.sgh && dsec < 0; gy++) {
                for (Integer gx = 0; gx < d.sgw; gx++) {
                    if (d.secGrid.get(gy * d.sgw + gx) == bs) {
                        dsec = bs;
                        dcx = d.minX + gx * CELL + CELL / 2;
                        dcy = d.minY + gy * CELL + CELL / 2;
                        break;
                    }
                }
            }
        }
        if (dsec >= 0) {
            Boolean closedLOS = d.hasLOS(dcx - 24, dcy, dcx + 24, dcy);
            Integer savedCeil = d.secCeil.get(dsec);
            d.secCeil.set(dsec, d.secOpenCeil.get(dsec));      // abre a porta
            Boolean openLOS = d.hasLOS(dcx - 24, dcy, dcx + 24, dcy);
            d.secCeil.set(dsec, savedCeil);
            System.debug('LOS x porta: setor=' + dsec + ' fechada=' + closedLOS + ' aberta=' + openLOS + ' (esperado false, true)');
        }
    }

    /** RENDER DE SETORES (portal walker): por coluna, atravessa os linedefs em
     *  ordem de distancia. Em cada cruzamento desenha o chao/teto do setor (na
     *  altura real), os degraus (upper/lower textures) e segue ate uma parede
     *  solida. E o que da a cara das salas do E1M1 (desniveis, batentes, ceu). */
    void renderRGB() {
        for (Integer col = 0; col < VW; col++) {
            Integer aoff = (col - VW / 2) * FOV / VW;
            Integer ray = gang - aoff;   // coluna cresce p/ direita -> angulo decresce (sem espelhar)
            // direcao em escala reduzida (~64) pros produtos cruzados caberem em int 32-bit
            Integer rdx = cosT(ray) / 256;
            Integer rdy = sinT(ray) / 256;
            Integer fdx = cosT(ray); Integer fdy = sinT(ray);   // direcao p/ flat casting (escala S)
            Integer ca = cosT(aoff); if (ca < 1) ca = 1;        // correcao fisheye
            zbuf.set(col, MAXD);

            // coleta TODAS as interseccoes raio x linha (perp, linha, snum, den, near-front)
            List<Integer> hP = new List<Integer>(); List<Integer> hL = new List<Integer>();
            List<Integer> hS = new List<Integer>(); List<Integer> hD = new List<Integer>(); List<Integer> hF = new List<Integer>();
            for (Integer i = 0; i < nlines; i++) {
                Integer ex = lex.get(i); Integer ey = ley.get(i);
                Integer den = rdx * ey - rdy * ex;        // cross(dir, e)
                if (den == 0) continue;
                Integer ax = lax.get(i) - gpx; Integer ay = lay.get(i) - gpy;
                Integer tnum = ax * ey - ay * ex;         // t = tnum/den (distancia)
                Integer snum = ax * rdy - ay * rdx;       // s = snum/den (posicao na parede)
                Boolean ok;
                if (den > 0) ok = (tnum >= 0) && (snum >= 0) && (snum <= den);
                else ok = (tnum <= 0) && (snum <= 0) && (snum >= den);
                if (!ok) continue;
                Integer ddx = rdx * tnum / den; Integer ddy = rdy * tnum / den;
                Integer perp = isqrt(ddx * ddx + ddy * ddy) * ca / S;
                if (perp < 1) perp = 1;
                // near-front: o player esta no lado direito (front) de v1->v2?
                Integer crossP = ex * (gpy - lay.get(i)) - ey * (gpx - lax.get(i));
                hP.add(perp); hL.add(i); hS.add(snum); hD.add(den); hF.add((crossP < 0) ? 1 : 0);
            }
            // insertion sort por distancia crescente
            for (Integer a = 1; a < hP.size(); a++) {
                Integer p = hP.get(a); Integer l = hL.get(a); Integer s2 = hS.get(a); Integer d2 = hD.get(a); Integer ff = hF.get(a);
                Integer bq = a - 1;
                while (bq >= 0 && hP.get(bq) > p) {
                    hP.set(bq + 1, hP.get(bq)); hL.set(bq + 1, hL.get(bq)); hS.set(bq + 1, hS.get(bq)); hD.set(bq + 1, hD.get(bq)); hF.set(bq + 1, hF.get(bq));
                    bq--;
                }
                hP.set(bq + 1, p); hL.set(bq + 1, l); hS.set(bq + 1, s2); hD.set(bq + 1, d2); hF.set(bq + 1, ff);
            }

            // caminha os cruzamentos: preenche teto/chao e degraus, estreita o clip
            Integer clipTop = 0; Integer clipBot = VH - 1; Boolean done = false;
            for (Integer hi = 0; hi < hP.size(); hi++) {
                if (done) break;
                Integer D = hP.get(hi); Integer i = hL.get(hi); Integer nf = hF.get(hi);
                Integer near = (nf == 1) ? lFrontSec.get(i) : lBackSec.get(i);
                Integer far  = (nf == 1) ? lBackSec.get(i)  : lFrontSec.get(i);
                if (near < 0) { near = lFrontSec.get(i); far = lBackSec.get(i); nf = 1; }
                Integer xoff = (nf == 1) ? lfX.get(i) : lbX.get(i);
                Integer u = hS.get(hi) * lLen.get(i) / hD.get(hi) + xoff;
                Integer yC = horiz - (secCeil.get(near) - eyeZ) * projS / D;   // linha do teto
                Integer yF = horiz - (secFloor.get(near) - eyeZ) * projS / D;  // linha do chao
                Boolean nearSky = secSky.get(near) == 1;

                castPlane(col, clipTop, (yC - 1 < clipBot ? yC - 1 : clipBot), near, true, fdx, fdy, ca);   // teto
                castPlane(col, (yF + 1 > clipTop ? yF + 1 : clipTop), clipBot, near, false, fdx, fdy, ca);  // chao
                Integer wTop = (yC > clipTop ? yC : clipTop);
                Integer wBot = (yF < clipBot ? yF : clipBot);

                if (far < 0) {                                                  // parede solida: fecha a coluna
                    Integer tex = (nf == 1) ? lfMid.get(i) : lbMid.get(i);
                    wallSpan(col, wTop, wBot, tex, secCeil.get(near), D, u, secLight.get(near));
                    zbuf.set(col, D);
                    done = true;
                } else {                                                       // portal: degraus + segue
                    Integer ybC = horiz - (secCeil.get(far) - eyeZ) * projS / D;
                    Integer ybF = horiz - (secFloor.get(far) - eyeZ) * projS / D;
                    if (secCeil.get(far) < secCeil.get(near) && !nearSky) {     // teto desce -> upper texture
                        Integer tex = (nf == 1) ? lfUp.get(i) : lbUp.get(i);
                        wallSpan(col, wTop, (ybC - 1 < wBot ? ybC - 1 : wBot), tex, secCeil.get(near), D, u, secLight.get(near));
                    }
                    if (secFloor.get(far) > secFloor.get(near)) {              // chao sobe -> lower texture (degrau)
                        Integer tex = (nf == 1) ? lfLo.get(i) : lbLo.get(i);
                        wallSpan(col, (ybF + 1 > wTop ? ybF + 1 : wTop), wBot, tex, secFloor.get(far), D, u, secLight.get(near));
                    }
                    Integer nTop = (ybC > wTop ? ybC : wTop);                  // estreita o clip pra abertura
                    Integer nBot = (ybF < wBot ? ybF : wBot);
                    if (nTop > clipTop) clipTop = nTop;
                    if (nBot < clipBot) clipBot = nBot;
                    if (clipTop > clipBot) done = true;
                }
            }
            if (!done) for (Integer y = clipTop; y <= clipBot; y++) fb.set(col + y * VW, rgb(8, 8, 12));
        }
    }

    /** preenche o chao OU teto de um setor numa faixa de linhas, amostrando o flat
     *  real com perspectiva (distancia por linha) + luz do setor. Ceu se for sky. */
    void castPlane(Integer col, Integer y0, Integer y1, Integer sec, Boolean ceil,
                   Integer fdx, Integer fdy, Integer ca) {
        if (y0 < 0) y0 = 0; if (y1 > VH - 1) y1 = VH - 1; if (y0 > y1) return;
        Boolean sky = ceil && secSky.get(sec) == 1;
        Integer zPlane = ceil ? secCeil.get(sec) : secFloor.get(sec);
        Integer flatIdx = ceil ? secCeilFlat.get(sec) : secFloorFlat.get(sec);
        Integer light = secLight.get(sec);
        Integer fbase = flatFp + flatIdx * 4096;
        Integer dz = zPlane - eyeZ; if (dz < 0) dz = -dz;
        for (Integer y = y0; y <= y1; y++) {
            if (sky) { drawSky(col, y); continue; }
            Integer denom = horiz - y; if (denom < 0) denom = -denom; if (denom < 1) denom = 1;
            Integer rowD = dz * projS / denom; if (rowD > MAXD) rowD = MAXD; if (rowD < 1) rowD = 1;
            Integer actual = rowD * S / ca;
            Integer fx = gpx + fdx * actual / S;
            Integer fy = gpy + fdy * actual / S;
            Integer pidx = w.b.get(fbase + pmod(fy, 64) * 64 + pmod(fx, 64));
            Integer base = pal.get(pidx);
            Integer sh = light - rowD / 12; if (sh < 24) sh = 24; if (sh > 255) sh = 255;
            fb.set(col + y * VW, rgb((base / 65536) * sh / 256, Math.mod(base / 256, 256) * sh / 256, Math.mod(base, 256) * sh / 256));
        }
    }

    /** desenha uma faixa de parede texturizada. zTop = altura (mundo) do topo da
     *  superficie; V vem da altura real de cada pixel (perspectiva correta). */
    void wallSpan(Integer col, Integer y0, Integer y1, Integer texIdx, Integer zTop,
                  Integer D, Integer u, Integer light) {
        if (texIdx == 65535) return;                  // lado sem textura ("-")
        if (y0 < 0) y0 = 0; if (y1 > VH - 1) y1 = VH - 1; if (y0 > y1) return;
        Integer twv = tW.get(texIdx); Integer thv = tH.get(texIdx); Integer toffv = tOff.get(texIdx);
        Integer colBase = texpixFp + toffv + pmod(u, twv) * thv;
        Integer sh = light - D / 12; if (sh < 24) sh = 24; if (sh > 255) sh = 255;
        for (Integer y = y0; y <= y1; y++) {
            Integer worldZ = eyeZ + (horiz - y) * D / projS;
            Integer v = pmod(zTop - worldZ, thv);
            Integer base = pal.get(w.b.get(colBase + v));
            fb.set(col + y * VW, rgb((base / 65536) * sh / 256, Math.mod(base / 256, 256) * sh / 256, Math.mod(base, 256) * sh / 256));
        }
    }

    /** pixel de ceu: textura SKY1 mapeada pelo angulo de visao (repete 4x no circulo) */
    void drawSky(Integer col, Integer y) {
        Integer twv = tW.get(skyTexIdx); Integer thv = tH.get(skyTexIdx); Integer toffv = tOff.get(skyTexIdx);
        Integer aoff = (col - VW / 2) * FOV / VW;
        Integer su = pmod((gang - aoff) * twv / 256, twv);
        Integer sv = y * thv / horiz; if (sv >= thv) sv = thv - 1; if (sv < 0) sv = 0;
        fb.set(col + y * VW, pal.get(w.b.get(texpixFp + toffv + su * thv + sv)));
    }

    void drawLineFb(Integer x0, Integer y0, Integer x1, Integer y1, Integer c) {
        Integer dx = Math.abs(x1 - x0); Integer dy = Math.abs(y1 - y0);
        Integer sx = (x0 < x1) ? 1 : -1; Integer sy = (y0 < y1) ? 1 : -1;
        Integer err = dx - dy; Integer x = x0; Integer y = y0;
        for (Integer g = 0; g < 5000; g++) {
            if (x >= 0 && x < VW && y >= 0 && y < VH) fb.set(x + y * VW, c);
            if (x == x1 && y == y1) return;
            Integer e2 = err * 2;
            if (e2 > -dy) { err -= dy; x += sx; }
            if (e2 < dx) { err += dx; y += sy; }
        }
    }

    /** automap (TAB): desenha o E1M1 de cima — paredes, inimigos vivos e o jogador */
    void drawAutomap() {
        Integer botY = VH - hudH;
        for (Integer y = 0; y < botY; y++)
            for (Integer x = 0; x < VW; x++) fb.set(x + y * VW, rgb(10, 10, 14));
        Integer spanX = maxXw - minX; if (spanX < 1) spanX = 1;
        Integer spanY = maxYw - minY; if (spanY < 1) spanY = 1;
        Integer scX = (VW - 16) * 256 / spanX; Integer scY = (botY - 16) * 256 / spanY;
        Integer sc = (scX < scY) ? scX : scY;
        for (Integer i = 0; i < w.lv1.size(); i++) {
            Integer a = w.lv1.get(i); Integer b = w.lv2.get(i);
            Integer xa = 8 + (w.vx.get(a) - minX) * sc / 256;
            Integer ya = 8 + (maxYw - w.vy.get(a)) * sc / 256;
            Integer xb = 8 + (w.vx.get(b) - minX) * sc / 256;
            Integer yb = 8 + (maxYw - w.vy.get(b)) * sc / 256;
            drawLineFb(xa, ya, xb, yb, (w.ltwo.get(i) == 0) ? rgb(210, 205, 195) : rgb(95, 80, 65));
        }
        for (Integer i = 0; i < nent; i++) {
            if (enState.get(i) != 0) continue;
            Integer ex = 8 + (enX.get(i) - minX) * sc / 256;
            Integer ey = 8 + (maxYw - enY.get(i)) * sc / 256;
            for (Integer dy = -1; dy <= 1; dy++) for (Integer dx = -1; dx <= 1; dx++) {
                Integer xx = ex + dx; Integer yy = ey + dy;
                if (xx >= 0 && xx < VW && yy >= 0 && yy < botY) fb.set(xx + yy * VW, rgb(255, 70, 70));
            }
        }
        Integer px = 8 + (gpx - minX) * sc / 256;
        Integer py = 8 + (maxYw - gpy) * sc / 256;
        Integer ax = 8 + (gpx + cosT(gang) * 220 / S - minX) * sc / 256;
        Integer ay = 8 + (maxYw - (gpy + sinT(gang) * 220 / S)) * sc / 256;
        drawLineFb(px, py, ax, ay, rgb(90, 255, 90));
        for (Integer dy = -2; dy <= 2; dy++) for (Integer dx = -2; dx <= 2; dx++) {
            Integer xx = px + dx; Integer yy = py + dy;
            if (xx >= 0 && xx < VW && yy >= 0 && yy < botY) fb.set(xx + yy * VW, rgb(90, 255, 90));
        }
    }
}
