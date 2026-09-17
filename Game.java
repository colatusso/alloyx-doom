import javax.swing.*;
import java.awt.*;
import java.awt.event.*;
import java.awt.image.*;
import javax.sound.sampled.*;
import javax.sound.midi.*;

/**
 * Game — host de tempo real para o DOOM cujo ENGINE e Apex (Doom.cls / Wad.cls),
 * transpilado para Java pelo AlloyX. Este host so abre a janela, le o teclado e
 * desenha o framebuffer RGB que o Apex calcula a cada frame. Toda a logica do jogo
 * (parse do WAD oficial, raycasting, movimento, colisao) roda no codigo Apex.
 *
 * Controles: W/S frente/tras, A/D ou setas vira, Q/E strafe, ESC sai.
 */
public class Game {
    static final int IW = 400, IH = 250;   // resolucao interna (estilo DOOM, 16:10)
    static final int SCALE = 3;            // janela = 1200 x 750 (redimensionavel)
    static final boolean[] k = new boolean[64];

    public static void main(String[] args) throws Exception {
        // === engine Apex ===
        Doom engine = new Doom();
        engine.init(IW, IH);

        // === audio: banco de SFX do WAD (decodificado no Apex) -> Clips Java ===
        final SfxBank sfx = new SfxBank(engine.audioBank());
        startMusic(engine.musicBank());   // musica do mapa (MUS->MIDI no gerador) em loop

        // buffer de pixels ligado direto na BufferedImage (sem copia extra)
        final BufferedImage img = new BufferedImage(IW, IH, BufferedImage.TYPE_INT_RGB);
        final int[] px = ((DataBufferInt) img.getRaster().getDataBuffer()).getData();

        final JPanel panel = new JPanel() {
            @Override protected void paintComponent(Graphics g) {
                super.paintComponent(g);
                ((Graphics2D) g).setRenderingHint(RenderingHints.KEY_INTERPOLATION,
                        RenderingHints.VALUE_INTERPOLATION_NEAREST_NEIGHBOR);
                g.drawImage(img, 0, 0, getWidth(), getHeight(), null);   // escala p/ o tamanho atual
            }
        };
        panel.setPreferredSize(new Dimension(IW * SCALE, IH * SCALE));
        panel.setFocusable(true);
        panel.addKeyListener(new KeyAdapter() {
            @Override public void keyPressed(KeyEvent e)  { set(e.getKeyCode(), true); }
            @Override public void keyReleased(KeyEvent e) { set(e.getKeyCode(), false); }
        });

        JFrame f = new JFrame("AlloyX DOOM — engine em Apex (E1M1, WAD oficial)");
        f.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        f.add(panel);
        f.pack();
        f.setResizable(true);
        f.setLocationRelativeTo(null);
        f.setVisible(true);
        panel.requestFocusInWindow();

        final int n = IW * IH;
        final long[] fps = {0, java.lang.System.nanoTime(), 0};
        final int[] curMap = {engine.mapIdx()};
        new Timer(16, e -> {
            alloyx.runtime.List<Integer> fb = engine.stepFrame(cmd());   // <- Apex renderiza
            for (int i = 0; i < n; i++) px[i] = fb.get(i);
            panel.repaint();
            alloyx.runtime.List<Integer> snd = engine.soundEvents();     // <- Apex enfileira sons
            for (int i = 0; i + 1 < snd.size(); i += 2) sfx.play(snd.get(i), snd.get(i + 1));
            int m = engine.mapIdx();                                      // trocou de mapa? troca a musica
            if (m != curMap[0]) { curMap[0] = m; startMusic(engine.musicBank()); }
            fps[0]++;
            long now = java.lang.System.nanoTime();
            if (now - fps[1] >= 1_000_000_000L) {
                f.setTitle("AlloyX DOOM — engine Apex (E1M1)  |  " + fps[0] + " fps");
                fps[0] = 0; fps[1] = now;
            }
        }).start();
    }

    static void set(int code, boolean down) {
        switch (code) {
            case KeyEvent.VK_W: case KeyEvent.VK_UP:    k[0] = down; break;  // frente
            case KeyEvent.VK_S: case KeyEvent.VK_DOWN:  k[1] = down; break;  // tras
            case KeyEvent.VK_A: case KeyEvent.VK_LEFT:  k[2] = down; break;  // vira esq
            case KeyEvent.VK_D: case KeyEvent.VK_RIGHT: k[3] = down; break;  // vira dir
            case KeyEvent.VK_Q: k[4] = down; break;                          // strafe esq
            case KeyEvent.VK_E: k[5] = down; break;                          // strafe dir
            case KeyEvent.VK_CONTROL: k[6] = down; break;                          // atirar
            case KeyEvent.VK_TAB: k[7] = down; break;                              // automap (segura)
            case KeyEvent.VK_SPACE: k[8] = down; break;                            // USE (abrir porta)
            case KeyEvent.VK_2: k[9] = down; break;                                // pistola
            case KeyEvent.VK_3: k[10] = down; break;                               // shotgun
            case KeyEvent.VK_4: k[11] = down; break;                               // chaingun
            case KeyEvent.VK_5: k[12] = down; break;                               // rocket
            case KeyEvent.VK_6: k[13] = down; break;                               // plasma
            case KeyEvent.VK_7: k[14] = down; break;                               // BFG
            case KeyEvent.VK_ESCAPE: java.lang.System.exit(0);
        }
    }

    static Sequencer music;   // sequencer atual (parado/reaberto a cada troca de mapa)

    /** toca a musica do mapa (bytes MIDI vindos do engine Apex) em loop continuo */
    static void startMusic(alloyx.runtime.List<Integer> midi) {
        try { if (music != null) { music.stop(); music.close(); music = null; } } catch (Exception ignore) {}
        if (midi == null || midi.size() == 0) return;
        try {
            byte[] data = new byte[midi.size()];
            for (int i = 0; i < data.length; i++) data[i] = (byte) (int) midi.get(i);
            music = MidiSystem.getSequencer();
            music.open();
            music.setSequence(new java.io.ByteArrayInputStream(data));
            music.setLoopCount(Sequencer.LOOP_CONTINUOUSLY);
            music.start();
        } catch (Exception ignore) { music = null; }   // sem MIDI disponivel -> jogo segue sem musica
    }

    // bitmask igual ao esperado por Doom.stepFrame
    static int cmd() {
        int c = 0;
        if (k[0]) c |= 1;
        if (k[1]) c |= 2;
        if (k[2]) c |= 4;
        if (k[3]) c |= 8;
        if (k[4]) c |= 16;
        if (k[5]) c |= 32;
        if (k[6]) c |= 64;
        if (k[7]) c |= 128;
        if (k[8]) c |= 256;
        if (k[9]) c |= 512;
        if (k[10]) c |= 1024;
        if (k[11]) c |= 2048;
        if (k[12]) c |= 4096;
        if (k[13]) c |= 8192;
        if (k[14]) c |= 16384;
        return c;
    }
}

/**
 * SfxBank — toca os SFX que o engine Apex decidiu disparar. O banco de PCM vem do
 * WAD oficial, decodificado no Apex (audioBank()); aqui so monta os Clips e toca.
 * O PCM do DOOM e 8-bit unsigned; convertido pra 16-bit signed (mais portavel).
 * Pool de vozes pre-abertas por som (sem abrir/fechar Clip por disparo: o churn
 * no mixer derrubava sons curtos quando varios tocavam no mesmo frame).
 */
class SfxBank {
    private final byte[][] pcm16;        // PCM 16-bit signed LE mono, por som
    private final int[] rate;            // taxa de amostragem por som
    private final Clip[][] voices;       // pool de vozes por som (abertas sob demanda, nunca fechadas)
    private static final int VOICES = 3; // sobreposicao maxima do MESMO som

    SfxBank(alloyx.runtime.List<Integer> bank) {
        int n = (bank.size() >= 2) ? bank.get(0) + bank.get(1) * 256 : 0;
        pcm16 = new byte[n][];
        rate = new int[n];
        voices = new Clip[n][VOICES];
        int p = 2;
        for (int s = 0; s < n; s++) {
            int r = bank.get(p) + bank.get(p + 1) * 256; p += 2;
            int len = bank.get(p) + bank.get(p + 1) * 256
                    + bank.get(p + 2) * 65536 + bank.get(p + 3) * 16777216; p += 4;
            byte[] out = new byte[len * 2];
            for (int i = 0; i < len; i++) {
                int s16 = (bank.get(p + i) - 128) << 8;     // 8-bit unsigned -> 16-bit signed
                out[i * 2] = (byte) (s16 & 0xFF);
                out[i * 2 + 1] = (byte) ((s16 >> 8) & 0xFF);
            }
            p += len;
            pcm16[s] = out;
            rate[s] = r;
        }
    }

    void play(int id, int vol) {
        if (id < 0 || id >= pcm16.length || pcm16[id] == null) return;
        try {
            Clip[] vs = voices[id];
            Clip free = null;
            for (Clip c : vs) if (c != null && !c.isRunning()) { free = c; break; }   // voz parada -> reusa
            if (free == null) {
                for (int v = 0; v < vs.length; v++) {
                    if (vs[v] == null) {                                              // abre voz nova (1x)
                        Clip c = AudioSystem.getClip();
                        c.open(new AudioFormat(rate[id], 16, 1, true, false), pcm16[id], 0, pcm16[id].length);
                        vs[v] = c; free = c; break;
                    }
                }
            }
            if (free == null) { free = vs[0]; free.stop(); }                          // todas tocando -> rouba
            free.setFramePosition(0);
            try {
                FloatControl g = (FloatControl) free.getControl(FloatControl.Type.MASTER_GAIN);
                float db = (vol >= 255) ? 0f : (float) (20.0 * Math.log10(Math.max(1, vol) / 255.0));
                g.setValue(Math.max(g.getMinimum(), Math.min(g.getMaximum(), db)));
            } catch (Exception ignore) {}
            free.start();
        } catch (Exception ignore) {}   // sem audio disponivel -> jogo segue mudo
    }
}
