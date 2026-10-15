// Image helpers for generuj.ps1 and zostav.ps1 (compiled by Add-Type; C# 5, System.Drawing only).
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

public class Obr
{
    public int W, H;
    public float[] R, G, B;   // 0..255

    public Obr(int w, int h)
    {
        W = w; H = h;
        R = new float[w * h]; G = new float[w * h]; B = new float[w * h];
    }

    public static Size VelkostSuboru(string path)
    {
        using (var img = Image.FromFile(path)) { return img.Size; }
    }

    // Loads an image resized to w x h. mode: 0 = stretch, 1 = cover (centre crop), 2 = contain (white padding).
    public static Obr Nacitaj(string path, int w, int h, int mode)
    {
        using (var src = Image.FromFile(path))
        using (var bmp = new Bitmap(w, h, PixelFormat.Format24bppRgb))
        {
            using (var g = Graphics.FromImage(bmp))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.Clear(Color.White);
                Rectangle srcRect = new Rectangle(0, 0, src.Width, src.Height);
                Rectangle dstRect = new Rectangle(0, 0, w, h);
                if (mode == 1)
                {
                    double s = Math.Max((double)w / src.Width, (double)h / src.Height);
                    int cw = (int)(w / s), ch = (int)(h / s);
                    srcRect = new Rectangle((src.Width - cw) / 2, (src.Height - ch) / 2, cw, ch);
                }
                else if (mode == 2)
                {
                    double s = Math.Min((double)w / src.Width, (double)h / src.Height) * 0.92;
                    int dw = (int)(src.Width * s), dh = (int)(src.Height * s);
                    dstRect = new Rectangle((w - dw) / 2, (h - dh) / 2, dw, dh);
                }
                using (var ia = new ImageAttributes())
                {
                    ia.SetWrapMode(WrapMode.TileFlipXY);
                    g.DrawImage(src, dstRect, srcRect.X, srcRect.Y, srcRect.Width, srcRect.Height, GraphicsUnit.Pixel, ia);
                }
            }
            return ZBitmapy(bmp);
        }
    }

    // Loads a generated image into the base frame (w x h) using the alignment t = {sx, sy, dx, dy}
    // found by Zarovnanie.Najdi: base pixel u maps to (u - w/2) * sx + w/2 + dx in the result
    // stretched to w x h.
    public static Obr NacitajZarovnane(string path, int w, int h, double[] t)
    {
        using (var src = Image.FromFile(path))
        using (var bmp = new Bitmap(w, h, PixelFormat.Format24bppRgb))
        {
            double kx = (double)src.Width / w, ky = (double)src.Height / h;
            float x0 = (float)((w / 2.0 - w / 2.0 * t[0] + t[2]) * kx);
            float y0 = (float)((h / 2.0 - h / 2.0 * t[1] + t[3]) * ky);
            using (var g = Graphics.FromImage(bmp))
            using (var ia = new ImageAttributes())
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                ia.SetWrapMode(WrapMode.TileFlipXY);
                g.DrawImage(src, new Rectangle(0, 0, w, h), x0, y0, (float)(w * t[0] * kx), (float)(h * t[1] * ky), GraphicsUnit.Pixel, ia);
            }
            return ZBitmapy(bmp);
        }
    }

    // Loads the part [x0, x1) x [y0, y1) (relative coordinates) of a file, at most maxW wide.
    public static Obr NacitajVyrez(string path, double x0, double y0, double x1, double y1, int maxW)
    {
        using (var src = Image.FromFile(path))
        {
            int ax = (int)(x0 * src.Width), ay = (int)(y0 * src.Height);
            int sw = (int)(x1 * src.Width) - ax, sh = (int)(y1 * src.Height) - ay;
            double s = Math.Min(1.0, (double)maxW / sw);
            int w = (int)(sw * s), h = (int)(sh * s);
            using (var bmp = new Bitmap(w, h, PixelFormat.Format24bppRgb))
            {
                using (var g = Graphics.FromImage(bmp))
                {
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.DrawImage(src, new Rectangle(0, 0, w, h), ax, ay, sw, sh, GraphicsUnit.Pixel);
                }
                return ZBitmapy(bmp);
            }
        }
    }

    // Copy in which the pixels inside each rectangle q (normalised quads) are taken from
    // (x + dx_q, y + dy_q); see Zarovnanie.Posuny.
    public Obr Posun(double[] quads, int[] d)
    {
        var o = Kopia();
        for (int q = 0; q + 3 < quads.Length; q += 4)
        {
            int dx = d[q / 2], dy = d[q / 2 + 1];
            if (dx == 0 && dy == 0) continue;
            int x0 = (int)(quads[q] * W), y0 = (int)(quads[q + 1] * H), x1 = (int)(quads[q + 2] * W), y1 = (int)(quads[q + 3] * H);
            for (int y = Math.Max(0, y0); y < Math.Min(H, y1); y++)
                for (int x = Math.Max(0, x0); x < Math.Min(W, x1); x++)
                {
                    int sx = Math.Min(W - 1, Math.Max(0, x + dx)), sy = Math.Min(H - 1, Math.Max(0, y + dy));
                    int s = sy * W + sx, t = y * W + x;
                    o.R[t] = R[s]; o.G[t] = G[s]; o.B[t] = B[s];
                }
        }
        return o;
    }

    // Box-average downscale by an integer factor.
    public Obr Zmensi(int f)
    {
        var o = new Obr(W / f, H / f);
        for (int y = 0; y < o.H; y++)
            for (int x = 0; x < o.W; x++)
            {
                float r = 0, g = 0, b = 0;
                for (int j = 0; j < f; j++)
                    for (int i = 0; i < f; i++)
                    {
                        int p = (y * f + j) * W + x * f + i;
                        r += R[p]; g += G[p]; b += B[p];
                    }
                int t = y * o.W + x;
                o.R[t] = r / (f * f); o.G[t] = g / (f * f); o.B[t] = b / (f * f);
            }
        return o;
    }

    static Obr ZBitmapy(Bitmap bmp)
    {
        int w = bmp.Width, h = bmp.Height;
        var o = new Obr(w, h);
        var d = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
        var buf = new byte[d.Stride * h];
        Marshal.Copy(d.Scan0, buf, 0, buf.Length);
        bmp.UnlockBits(d);
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                int i = y * d.Stride + x * 3, p = y * w + x;
                o.B[p] = buf[i]; o.G[p] = buf[i + 1]; o.R[p] = buf[i + 2];
            }
        return o;
    }

    public Obr Vyrez(double x0, double y0, double x1, double y1)
    {
        int ax = (int)(x0 * W), ay = (int)(y0 * H), bx = (int)(x1 * W), by = (int)(y1 * H);
        var o = new Obr(bx - ax, by - ay);
        for (int y = 0; y < o.H; y++)
            for (int x = 0; x < o.W; x++)
            {
                int s = (y + ay) * W + x + ax, t = y * o.W + x;
                o.R[t] = R[s]; o.G[t] = G[s]; o.B[t] = B[s];
            }
        return o;
    }

    public void UlozJpg(string path, long kvalita)
    {
        using (var bmp = NaBitmapu(null, 0, 0, W, H))
        {
            ImageCodecInfo codec = null;
            foreach (var c in ImageCodecInfo.GetImageEncoders()) if (c.MimeType == "image/jpeg") codec = c;
            var ep = new EncoderParameters(1);
            ep.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, kvalita);
            bmp.Save(path, codec, ep);
        }
    }

    // Saves the region (x, y, w, h) as RGBA PNG with the given alpha (0..1, full-size array).
    public void UlozPng(string path, float[] alfa, int x, int y, int w, int h)
    {
        using (var bmp = NaBitmapu(alfa, x, y, w, h)) { bmp.Save(path, ImageFormat.Png); }
    }

    Bitmap NaBitmapu(float[] alfa, int x0, int y0, int w, int h)
    {
        var fmt = alfa == null ? PixelFormat.Format24bppRgb : PixelFormat.Format32bppArgb;
        int bpp = alfa == null ? 3 : 4;
        var bmp = new Bitmap(w, h, fmt);
        var d = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, fmt);
        var buf = new byte[d.Stride * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                int p = (y + y0) * W + x + x0, i = y * d.Stride + x * bpp;
                // Fully transparent pixels stay black so the PNG compresses well.
                if (alfa != null && alfa[p] < 0.002f) continue;
                buf[i] = K(B[p]); buf[i + 1] = K(G[p]); buf[i + 2] = K(R[p]);
                if (alfa != null) buf[i + 3] = K(alfa[p] * 255f);
            }
        Marshal.Copy(buf, 0, d.Scan0, buf.Length);
        bmp.UnlockBits(d);
        return bmp;
    }

    static byte K(float v) { return (byte)(v < 0 ? 0 : v > 255 ? 255 : v + 0.5f); }

    public Obr Rozmaz(int r)
    {
        var o = new Obr(W, H);
        o.R = Mapa.Rozmaz(R, W, H, r); o.G = Mapa.Rozmaz(G, W, H, r); o.B = Mapa.Rozmaz(B, W, H, r);
        return o;
    }

    // Weighted blur (normalised convolution): pixels with weight 0 (objects) do not
    // contribute; where no weighted pixel is near, falls back to the plain blur.
    public Obr RozmazVazene(float[] w, int r)
    {
        var sw = Mapa.Rozmaz(w, W, H, r);
        var plain = Rozmaz(r);
        var o = new Obr(W, H);
        float[][] src = { R, G, B }, dst = { o.R, o.G, o.B }, pl = { plain.R, plain.G, plain.B };
        for (int c = 0; c < 3; c++)
        {
            var prod = new float[w.Length];
            for (int i = 0; i < w.Length; i++) prod[i] = src[c][i] * w[i];
            var sp = Mapa.Rozmaz(prod, W, H, r);
            for (int i = 0; i < w.Length; i++)
            {
                float k = Math.Min(1f, sw[i] / 0.15f);   // confidence of the weighted estimate
                float wv = sw[i] > 1e-4f ? sp[i] / sw[i] : pl[c][i];
                dst[c][i] = wv * k + pl[c][i] * (1 - k);
            }
        }
        return o;
    }

    // Per-pixel colour difference (max over channels) of two images of equal size.
    public static float[] Rozdiel(Obr a, Obr b)
    {
        var d = new float[a.W * a.H];
        for (int i = 0; i < d.Length; i++)
            d[i] = Math.Max(Math.Abs(a.R[i] - b.R[i]), Math.Max(Math.Abs(a.G[i] - b.G[i]), Math.Abs(a.B[i] - b.B[i])));
        return d;
    }

    // Draws src over this image with the given alpha (full-size arrays, same dimensions).
    public void Prekry(Obr src, float[] alfa)
    {
        for (int i = 0; i < R.Length; i++)
        {
            float a = alfa[i];
            if (a <= 0) continue;
            R[i] += (src.R[i] - R[i]) * a; G[i] += (src.G[i] - G[i]) * a; B[i] += (src.B[i] - B[i]) * a;
        }
    }

    // Moves the wall-like pixels of an object layer (generated on the base walls) to the
    // colour of another background: out = layer + (plateLow - baseLow) * (1 - objectness),
    // where objectness grows with the distance of the layer pixel from the local base colour.
    // Low-frequency images (heavy blur) carry the wall colour; the object itself stays untouched.
    public static Obr Prefarbi(Obr layer, Obr baseLow, Obr plateLow, float t0, float t1)
    {
        var o = new Obr(layer.W, layer.H);
        for (int i = 0; i < layer.R.Length; i++)
        {
            float dist = Math.Max(Math.Abs(layer.R[i] - baseLow.R[i]), Math.Max(Math.Abs(layer.G[i] - baseLow.G[i]), Math.Abs(layer.B[i] - baseLow.B[i])));
            float bg = 1f - Math.Min(1f, Math.Max(0f, (dist - t0) / (t1 - t0)));
            o.R[i] = layer.R[i] + (plateLow.R[i] - baseLow.R[i]) * bg;
            o.G[i] = layer.G[i] + (plateLow.G[i] - baseLow.G[i]) * bg;
            o.B[i] = layer.B[i] + (plateLow.B[i] - baseLow.B[i]) * bg;
        }
        return o;
    }

    // Chroma key: how pure green a pixel is (an object the model painted #00FF00),
    // soft threshold of G - max(R, B).
    public float[] Zelena(float t0, float t1)
    {
        var o = new float[R.Length];
        for (int i = 0; i < o.Length; i++)
        {
            float v = G[i] - Math.Max(R[i], B[i]);
            o[i] = Math.Min(1f, Math.Max(0f, (v - t0) / (t1 - t0)));
        }
        return o;
    }

    // Seamless tone matching of a layer to the image under it: a smooth field equal to
    // (under - layer) where the layer is not used (alfa ~ 0) and diffused inside the layer,
    // solved on a grid of f x f pixel cells. Diffusion between neighbouring cells is weighted by
    // how similar the layer's colours are (sigma), so a shelf is matched to the shelf around it
    // and a wall to the wall. Add the result to the layer with Pripocitaj.
    public static Obr Vyrovnanie(Obr under, Obr layer, float[] alfa, int f, int iters, float sigma)
    {
        int W0 = under.W, H0 = under.H, w = W0 / f + 1, h = H0 / f + 1;
        var known = new bool[w * h];
        var d = new float[3][] { new float[w * h], new float[w * h], new float[w * h] };
        var m = new float[3][] { new float[w * h], new float[w * h], new float[w * h] };
        var cnt = new int[w * h];
        var all = new int[w * h];
        var maxA = new float[w * h];
        float[][] u = { under.R, under.G, under.B }, l = { layer.R, layer.G, layer.B };
        for (int y = 0; y < H0; y++)
            for (int x = 0; x < W0; x++)
            {
                int p = y * W0 + x, c = (y / f) * w + x / f;
                if (alfa[p] > maxA[c]) maxA[c] = alfa[p];
                for (int k = 0; k < 3; k++) m[k][c] += l[k][p];
                all[c]++;
                if (alfa[p] < 0.02f) { for (int k = 0; k < 3; k++) d[k][c] += u[k][p] - l[k][p]; cnt[c]++; }
            }
        for (int c = 0; c < w * h; c++)
        {
            known[c] = maxA[c] < 0.02f && cnt[c] > 0;
            for (int k = 0; k < 3; k++) { d[k][c] = known[c] ? d[k][c] / cnt[c] : 0; m[k][c] /= Math.Max(1, all[c]); }
        }
        // weights to the right and down neighbour, by colour similarity of the layer
        var wr = new float[w * h]; var wd = new float[w * h];
        float s2 = 2 * sigma * sigma;
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                int c = y * w + x;
                if (x + 1 < w) { float e = 0; for (int k = 0; k < 3; k++) { float t = m[k][c] - m[k][c + 1]; e += t * t; } wr[c] = (float)Math.Exp(-e / s2); }
                if (y + 1 < h) { float e = 0; for (int k = 0; k < 3; k++) { float t = m[k][c] - m[k][c + w]; e += t * t; } wd[c] = (float)Math.Exp(-e / s2); }
            }
        for (int k = 0; k < 3; k++)
        {
            var a = d[k];
            var b = new float[w * h];
            for (int it = 0; it < iters; it++)
            {
                for (int y = 0; y < h; y++)
                    for (int x = 0; x < w; x++)
                    {
                        int c = y * w + x;
                        if (known[c]) { b[c] = a[c]; continue; }
                        float sw = 0, sv = 0;
                        if (x > 0) { sw += wr[c - 1]; sv += wr[c - 1] * a[c - 1]; }
                        if (x + 1 < w) { sw += wr[c]; sv += wr[c] * a[c + 1]; }
                        if (y > 0) { sw += wd[c - w]; sv += wd[c - w] * a[c - w]; }
                        if (y + 1 < h) { sw += wd[c]; sv += wd[c] * a[c + w]; }
                        b[c] = sw > 1e-6f ? sv / sw : a[c];
                    }
                var t = a; a = b; b = t;
            }
            d[k] = a;
        }
        var o = new Obr(W0, H0);
        float[][] oc = { o.R, o.G, o.B };
        for (int y = 0; y < H0; y++)
        {
            double gy = (y + 0.5) / f - 0.5; int y0 = Math.Max(0, Math.Min(h - 2, (int)Math.Floor(gy))); double fy = Math.Max(0, Math.Min(1, gy - y0));
            for (int x = 0; x < W0; x++)
            {
                double gx = (x + 0.5) / f - 0.5; int x0 = Math.Max(0, Math.Min(w - 2, (int)Math.Floor(gx))); double fx = Math.Max(0, Math.Min(1, gx - x0));
                int c = y0 * w + x0;
                for (int k = 0; k < 3; k++)
                    oc[k][y * W0 + x] = (float)((d[k][c] * (1 - fx) + d[k][c + 1] * fx) * (1 - fy) + (d[k][c + w] * (1 - fx) + d[k][c + w + 1] * fx) * fy);
            }
        }
        return o;
    }

    // this += add * weight (per pixel).
    public void Pripocitaj(Obr add, float[] weight)
    {
        for (int i = 0; i < R.Length; i++)
        {
            float a = weight[i];
            if (a <= 0) continue;
            R[i] += add.R[i] * a; G[i] += add.G[i] * a; B[i] += add.B[i] * a;
        }
    }

    // Grey image of a mask (for debugging).
    public static Obr ZMasky(float[] a, int w, int h)
    {
        var o = new Obr(w, h);
        for (int i = 0; i < a.Length; i++) { o.R[i] = o.G[i] = o.B[i] = a[i] * 255f; }
        return o;
    }

    // Copy scaled by k about the point (sx, sy) of this image, which moves to (dx, dy).
    public Obr Mierka(double sx, double sy, double dx, double dy, double k)
    {
        var o = new Obr(W, H);
        o.R = Mapa.Mierka(R, W, H, sx, sy, dx, dy, k);
        o.G = Mapa.Mierka(G, W, H, sx, sy, dx, dy, k);
        o.B = Mapa.Mierka(B, W, H, sx, sy, dx, dy, k);
        return o;
    }

    public Obr Kopia()
    {
        var o = new Obr(W, H);
        Array.Copy(R, o.R, R.Length); Array.Copy(G, o.G, G.Length); Array.Copy(B, o.B, B.Length);
        return o;
    }
}

// Operations on single-channel float maps (masks, differences).
public static class Mapa
{
    // Separable box blur, radius r, applied twice (close to Gaussian).
    public static float[] Rozmaz(float[] m, int w, int h, int r)
    {
        if (r <= 0) return (float[])m.Clone();
        var a = m;
        for (int pass = 0; pass < 2; pass++)
        {
            a = Smer(a, w, h, r, true, 0);
            a = Smer(a, w, h, r, false, 0);
        }
        return a;
    }

    public static float[] Rozsir(float[] m, int w, int h, int r) { return Smer(Smer(m, w, h, r, true, 1), w, h, r, false, 1); }
    public static float[] Zuz(float[] m, int w, int h, int r) { return Smer(Smer(m, w, h, r, true, -1), w, h, r, false, -1); }

    // mode 0 = mean (running sum), 1 = max, -1 = min over a 1-D window of radius r.
    static float[] Smer(float[] m, int w, int h, int r, bool horiz, int mode)
    {
        var o = new float[m.Length];
        int n = horiz ? w : h, lines = horiz ? h : w;
        Parallel.For(0, lines, l =>
        {
            int b = horiz ? l * w : l, s = horiz ? 1 : w;
            if (mode == 0)
            {
                double acc = 0;
                int lo = 0, hi = -1;
                for (int k = 0; k < n; k++)
                {
                    int nlo = Math.Max(0, k - r), nhi = Math.Min(n - 1, k + r);
                    while (hi < nhi) { hi++; acc += m[b + hi * s]; }
                    while (lo < nlo) { acc -= m[b + lo * s]; lo++; }
                    o[b + k * s] = (float)(acc / (hi - lo + 1));
                }
                return;
            }
            for (int k = 0; k < n; k++)
            {
                float acc = m[b + k * s];
                for (int j = Math.Max(0, k - r); j <= Math.Min(n - 1, k + r); j++)
                {
                    float v = m[b + j * s];
                    if (mode > 0) { if (v > acc) acc = v; }
                    else { if (v < acc) acc = v; }
                }
                o[b + k * s] = acc;
            }
        });
        return o;
    }

    public static float[] Min(float[] a, float[] b)
    {
        var o = new float[a.Length];
        for (int i = 0; i < a.Length; i++) o[i] = Math.Min(a[i], b[i]);
        return o;
    }

    // Mean of d where the weight is high (weight > 0.5); for consistency checks.
    public static double Priemer(float[] d, float[] weight)
    {
        double s = 0; long n = 0;
        for (int i = 0; i < d.Length; i++) if (weight[i] > 0.5f) { s += d[i]; n++; }
        return n == 0 ? 0 : s / n;
    }

    // Soft threshold: 0 below t0, 1 above t1, linear in between.
    public static float[] Prah(float[] d, float t0, float t1)
    {
        var o = new float[d.Length];
        for (int i = 0; i < d.Length; i++) o[i] = Math.Min(1f, Math.Max(0f, (d[i] - t0) / (t1 - t0)));
        return o;
    }

    // Zeroes everything outside the union of rectangles given as normalised [x0, y0, x1, y1] quads.
    public static void Oblast(float[] m, int w, int h, double[] rects)
    {
        var keep = new bool[m.Length];
        for (int k = 0; k + 3 < rects.Length; k += 4)
        {
            int x0 = (int)(rects[k] * w), y0 = (int)(rects[k + 1] * h), x1 = (int)(rects[k + 2] * w), y1 = (int)(rects[k + 3] * h);
            for (int y = Math.Max(0, y0); y < Math.Min(h, y1); y++)
                for (int x = Math.Max(0, x0); x < Math.Min(w, x1); x++) keep[y * w + x] = true;
        }
        for (int i = 0; i < m.Length; i++) if (!keep[i]) m[i] = 0;
    }

    // Clears the column [cx0, cx1) of mask a above the top edge of the object, so an object
    // standing behind it (a tap behind a washbasin) comes from the layer underneath.
    // The edge is the first run of `run` rows, between yFrom and yTo, in which most pixels of
    // a side strip (width `side`, left or right of the column) belong to the object in `own`.
    // Returns the edge row, or -1 (mask unchanged) when no edge is found.
    public static int OrezStlpec(float[] a, float[] own, int w, int h, double cx0, double cx1,
                                 double side, double yFrom, double yTo, int run)
    {
        int x0 = (int)(cx0 * w), x1 = (int)(cx1 * w), s = Math.Max(1, (int)(side * w));
        int ya = (int)(yFrom * h), yb = Math.Min(h, (int)(yTo * h));
        int rim = -1;
        int[][] strips = { new int[] { Math.Max(0, x0 - s), x0 }, new int[] { x1, Math.Min(w, x1 + s) } };
        foreach (var st in strips)
        {
            int streak = 0;
            for (int y = ya; y < yb; y++)
            {
                int hit = 0;
                for (int x = st[0]; x < st[1]; x++) if (own[y * w + x] > 0.5f) hit++;
                streak = hit * 2 >= (st[1] - st[0]) ? streak + 1 : 0;
                if (streak == run)
                {
                    int top = y - run + 1;
                    if (rim < 0 || top < rim) rim = top;
                    break;
                }
            }
        }
        if (rim < 0) return -1;
        for (int y = 0; y < rim; y++)
            for (int x = x0; x < x1; x++) a[y * w + x] = 0;
        return rim;
    }

    // 1 from row y0 (normalised) down, with a linear ramp of `feather` pixels above it.
    public static float[] Riadky(int w, int h, double y0, int feather)
    {
        var o = new float[w * h];
        int r = (int)(y0 * h);
        for (int y = Math.Max(0, r - feather); y < h; y++)
        {
            float v = y >= r ? 1f : 1f - (float)(r - y) / (feather + 1);
            for (int x = 0; x < w; x++) o[y * w + x] = v;
        }
        return o;
    }

    // Map scaled by k about the point (sx, sy), which moves to (dx, dy): every pixel p is sampled
    // bilinearly at s + (p - d) / k (clamped to the edges).
    public static float[] Mierka(float[] m, int w, int h, double sx, double sy, double dx, double dy, double k)
    {
        var o = new float[m.Length];
        Parallel.For(0, h, y =>
        {
            double qy = Math.Max(0, Math.Min(h - 1.001, sy + (y - dy) / k));
            int y0 = (int)qy; double fy = qy - y0;
            for (int x = 0; x < w; x++)
            {
                double qx = Math.Max(0, Math.Min(w - 1.001, sx + (x - dx) / k));
                int x0 = (int)qx; double fx = qx - x0;
                int c = y0 * w + x0;
                o[y * w + x] = (float)((m[c] * (1 - fx) + m[c + 1] * fx) * (1 - fy) + (m[c + w] * (1 - fx) + m[c + w + 1] * fx) * fy);
            }
        });
        return o;
    }

    // 1 inside the ellipse with normalised centre (cx, cy) and radii (rx, ry), falling linearly
    // to 0 over `feather` pixels inside its edge.
    public static float[] Elipsa(int w, int h, double cx, double cy, double rx, double ry, int feather)
    {
        var o = new float[w * h];
        double ax = rx * w, ay = ry * h, r = Math.Min(ax, ay), f = Math.Max(1, feather);
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                double dx = (x + 0.5 - cx * w) / ax, dy = (y + 0.5 - cy * h) / ay;
                double inside = (1 - Math.Sqrt(dx * dx + dy * dy)) * r;   // pixels from the edge
                o[y * w + x] = (float)Math.Max(0, Math.Min(1, inside / f));
            }
        return o;
    }

    public static float[] Doplnok(float[] a)
    {
        var o = new float[a.Length];
        for (int i = 0; i < a.Length; i++) o[i] = 1f - a[i];
        return o;
    }

    public static float[] Max(float[] a, float[] b)
    {
        var o = new float[a.Length];
        for (int i = 0; i < a.Length; i++) o[i] = Math.Max(a[i], b[i]);
        return o;
    }

    // Bounding box (x, y, w, h) of values above eps, padded by pad pixels.
    public static int[] Ohranicenie(float[] m, int w, int h, float eps, int pad)
    {
        int x0 = w, y0 = h, x1 = -1, y1 = -1;
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                if (m[y * w + x] > eps)
                {
                    if (x < x0) x0 = x; if (x > x1) x1 = x;
                    if (y < y0) y0 = y; if (y > y1) y1 = y;
                }
        if (x1 < 0) return new int[] { 0, 0, 0, 0 };
        x0 = Math.Max(0, x0 - pad); y0 = Math.Max(0, y0 - pad);
        x1 = Math.Min(w - 1, x1 + pad); y1 = Math.Min(h - 1, y1 + pad);
        return new int[] { x0, y0, x1 - x0 + 1, y1 - y0 + 1 };
    }
}

// Layers of the new approach (zostav2.ps1): an object cut out of its own generation so that the
// same layer fits every background (wall cladding).
public static class Vrstva
{
    // One RGBA layer of the object in c, whose background bg is c without the object (the empty
    // scene toned to c) and okraj the wall right behind its edge (from c itself: another
    // generation's wall differs in tone):
    // - the object (alfa) with its colour moved off the background it was generated on: an edge
    //   pixel is c = a f + (1 - a) okraj, so f = okraj + (c - okraj) / a (a light wall would
    //   otherwise stay as a halo around a dark object on a dark cladding); for a faint pixel that
    //   extrapolation runs off (a slightly darker wall would turn brown), so towards alpha 0.6 and
    //   below the object's own colour next to it (obj) is used,
    // - under it its shadow: the darkening of c against bg (luma of both blurred by rs), ignored
    //   below n0 (two generations never match exactly), full above n1, times the weight tien
    //   (1 next to the object, 0 farther than the shadow reaches). The blur leaves the object out,
    //   so its own dark edge does not read as a shadow next to it. A black pixel with alpha s
    //   darkens any background by the factor 1 - s. With posun > 0 bg is another generation (the
    //   empty scene), whose edges (the shelf's front edge) lie a few pixels elsewhere: of bg
    //   shifted by up to posun pixels, the luma closest to c's is used. With ostre >= 0 a thin
    //   strong darkening (a washbasin's contact shadow on the shelf, a band of a few pixels the
    //   blur rs washes out) counts too: measured with the blur ostre (0: none), ignored below
    //   0.2, full above 0.35 (the texture of two generations of the shelf stays below).
    // - the shadow is black, or where farebny (0..1, null: nowhere) has its own colour: a warm
    //   shadow on the light shelf is browner than the shelf, not just darker (black made it grey).
    //   Alpha S = the darkening of the darkest channel and colour F with F S + bg (1 - S) = c,
    //   which gives c again on bg. Only where the surface is the same on every cladding (the
    //   shelf): on a darker wall such a colour would lighten it.
    // Returns the alpha; the colour goes to farba.
    public static float[] Zloz(Obr c, Obr bg, Obr okraj, Obr obj, float[] alfa, float[] tien, float[] farebny, int rs, float n0, float n1, int posun, int ostre, out Obr farba)
    {
        int n = c.R.Length, cw = c.W, ch = c.H;
        var bl = okraj;
        var mimo = new float[n];
        for (int i = 0; i < n; i++) mimo[i] = 1f - Math.Min(1f, alfa[i] * 2f);
        var cb = c.RozmazVazene(mimo, rs);
        var bb = bg.RozmazVazene(mimo, rs);
        var lc = Luma(cb);
        var lb = Luma(bb);
        Obr cb2 = null, bb2 = null;
        float[] lc2 = null, lb2 = null;
        if (ostre >= 0) { cb2 = c.RozmazVazene(mimo, ostre); bb2 = bg.RozmazVazene(mimo, ostre); lc2 = Luma(cb2); lb2 = Luma(bb2); }
        var f = new Obr(cw, ch);
        var o = new float[n];
        Parallel.For(0, ch, y =>
        {
            for (int i = y * cw; i < (y + 1) * cw; i++)
            {
                float s = 0, sr = 0, sg = 0, sb = 0;
                if (tien[i] > 0)
                {
                    int j, j2;
                    float g, g2;
                    float k = Stmavenie(lc, lb, i, cw, ch, posun, n0, n1, out j, out g);
                    Obr cc = cb, bc = bb;
                    if (lc2 != null)
                    {
                        float k2 = Stmavenie(lc2, lb2, i, cw, ch, posun, 0.2f, 0.35f, out j2, out g2);
                        if (k2 * g2 > k * g) { k = k2; g = g2; j = j2; cc = cb2; bc = bb2; }
                    }
                    s = k * g;
                    float wf = farebny == null ? 0f : farebny[i];
                    if (wf > 0 && g > 0)
                    {
                        float rr = cc.R[i] / Math.Max(1f, bc.R[j]), rg = cc.G[i] / Math.Max(1f, bc.G[j]), rb = cc.B[i] / Math.Max(1f, bc.B[j]);
                        float S = 1f - Math.Min(1f, Math.Min(rr, Math.Min(rg, rb)));
                        if (S > 0.01f)
                        {
                            sr = wf * Math.Min(255f, Math.Max(0f, (cc.R[i] - bc.R[j] * (1 - S)) / S));
                            sg = wf * Math.Min(255f, Math.Max(0f, (cc.G[i] - bc.G[j] * (1 - S)) / S));
                            sb = wf * Math.Min(255f, Math.Max(0f, (cc.B[i] - bc.B[j] * (1 - S)) / S));
                        }
                        s = (1 - wf) * s + wf * S * g;
                    }
                    s = Math.Min(0.85f, s) * tien[i];
                }
                float a = alfa[i], A = a + (1 - a) * s;
                o[i] = A;
                if (A < 0.002f) continue;
                float w = a / A;
                f.R[i] = (1 - w) * sr;
                f.G[i] = (1 - w) * sg;
                f.B[i] = (1 - w) * sb;
                if (a < 0.002f) continue;   // shadow only
                float d = Math.Max(a, 0.6f), t = Math.Min(1f, Math.Max(0f, (a - 0.6f) / 0.4f));
                f.R[i] += w * (t * Math.Min(255f, Math.Max(0f, bl.R[i] + (c.R[i] - bl.R[i]) / d)) + (1 - t) * obj.R[i]);
                f.G[i] += w * (t * Math.Min(255f, Math.Max(0f, bl.G[i] + (c.G[i] - bl.G[i]) / d)) + (1 - t) * obj.G[i]);
                f.B[i] += w * (t * Math.Min(255f, Math.Max(0f, bl.B[i] + (c.B[i] - bl.B[i]) / d)) + (1 - t) * obj.B[i]);
            }
        });
        farba = f;
        return o;
    }

    static float[] Luma(Obr o)
    {
        var l = new float[o.R.Length];
        for (int i = 0; i < l.Length; i++) l[i] = 0.299f * o.R[i] + 0.587f * o.G[i] + 0.114f * o.B[i];
        return l;
    }

    // Darkening of luma lc against lb at pixel i (lb shifted by up to posun pixels: the value
    // closest to lc, its index goes to j); the weight g ignores it below n0, full above n1.
    static float Stmavenie(float[] lc, float[] lb, int i, int w, int h, int posun, float n0, float n1, out int j, out float g)
    {
        float yc = lc[i], yb = lb[i];
        j = i;
        int y = i / w, x = i - y * w, step = Math.Max(1, posun / 2);
        for (int dy = -posun; posun > 0 && dy <= posun; dy += step)
        {
            int yy = Math.Min(h - 1, Math.Max(0, y + dy));
            for (int dx = -posun; dx <= posun; dx += step)
            {
                int jj = yy * w + Math.Min(w - 1, Math.Max(0, x + dx));
                if (Math.Abs(lb[jj] - yc) < Math.Abs(yb - yc)) { yb = lb[jj]; j = jj; }
            }
        }
        float k = 1f - Math.Min(1f, yc / Math.Max(1f, yb));
        g = Math.Min(1f, Math.Max(0f, (k - n0) / (n1 - n0)));
        return k;
    }

    // Mask m with its holes filled: pixels below t that cannot reach the image's border through
    // other such pixels (the drain the model left metal, dark green, in a washbasin's green key).
    public static float[] Diery(float[] m, int w, int h, float t)
    {
        var von = new bool[m.Length];
        var q = new System.Collections.Generic.Queue<int>();
        Action<int> push = i => { if (!von[i] && m[i] < t) { von[i] = true; q.Enqueue(i); } };
        for (int x = 0; x < w; x++) { push(x); push((h - 1) * w + x); }
        for (int y = 0; y < h; y++) { push(y * w); push(y * w + w - 1); }
        while (q.Count > 0)
        {
            int i = q.Dequeue(), y = i / w, x = i - y * w;
            if (x > 0) push(i - 1);
            if (x < w - 1) push(i + 1);
            if (y > 0) push(i - w);
            if (y < h - 1) push(i + w);
        }
        var o = (float[])m.Clone();
        for (int i = 0; i < o.Length; i++) if (m[i] < t && !von[i]) o[i] = 1f;
        return o;
    }

    // Opacity of the object's edge: how far pixel c lies on the way from the wall behind it (wall)
    // to the object's own colour next to it (obj), i.e. the projection of c - wall on obj - wall.
    // A wall pixel gets 0 whatever its tone, an edge pixel its share of the object. Where object
    // and wall have nearly the same colour (|obj - wall| below minDist, chrome reflecting the
    // wall), the projection is noise and the pixel gets half of the outline.
    public static float[] Alfa(Obr c, Obr wall, Obr obj, float[] outline, float minDist)
    {
        int n = outline.Length;
        var a = new float[n];
        for (int i = 0; i < n; i++)
        {
            if (outline[i] <= 0) continue;
            float dr = obj.R[i] - wall.R[i], dg = obj.G[i] - wall.G[i], db = obj.B[i] - wall.B[i];
            float d2 = dr * dr + dg * dg + db * db;
            if (d2 < minDist * minDist) { a[i] = 0.5f * outline[i]; continue; }
            float p = ((c.R[i] - wall.R[i]) * dr + (c.G[i] - wall.G[i]) * dg + (c.B[i] - wall.B[i]) * db) / d2;
            a[i] = Math.Min(1f, Math.Max(0f, p)) * outline[i];
        }
        return a;
    }

    // The layer (colour f, alpha a) scaled by k about (sx, sy), which moves to (dx, dy); colour is
    // scaled premultiplied, so its edges do not darken towards the black of transparent pixels.
    public static float[] Mierka(Obr f, float[] a, double sx, double sy, double dx, double dy, double k, out Obr fs)
    {
        int w = f.W, h = f.H, n = a.Length;
        var p = new Obr(w, h);
        for (int i = 0; i < n; i++) { p.R[i] = f.R[i] * a[i]; p.G[i] = f.G[i] * a[i]; p.B[i] = f.B[i] * a[i]; }
        var ps = p.Mierka(sx, sy, dx, dy, k);
        var s = Mapa.Mierka(a, w, h, sx, sy, dx, dy, k);
        for (int i = 0; i < n; i++)
        {
            float d = s[i] > 1e-4f ? 1f / s[i] : 0f;
            ps.R[i] *= d; ps.G[i] *= d; ps.B[i] *= d;
        }
        fs = ps;
        return s;
    }

    // Colour difference (max over channels) of a to b, the smallest over b shifted by up to r
    // pixels in steps of `step`: edges a few pixels off (a bathtub rim, a joint) do not count.
    public static float[] RozdielPosun(Obr a, Obr b, int r, int step)
    {
        int w = a.W, h = a.H;
        var o = new float[w * h];
        Parallel.For(0, h, y =>
        {
            for (int x = 0; x < w; x++)
            {
                int i = y * w + x;
                float best = float.MaxValue;
                for (int dy = -r; dy <= r; dy += step)
                {
                    int yy = Math.Min(h - 1, Math.Max(0, y + dy));
                    for (int dx = -r; dx <= r; dx += step)
                    {
                        int j = yy * w + Math.Min(w - 1, Math.Max(0, x + dx));
                        float d = Math.Max(Math.Abs(a.R[i] - b.R[j]), Math.Max(Math.Abs(a.G[i] - b.G[j]), Math.Abs(a.B[i] - b.B[j])));
                        if (d < best) best = d;
                    }
                }
                o[i] = best;
            }
        });
        return o;
    }

    // The green key (painted by the model, often a little taller than the object, in places a
    // little lower) with its top at the object's top edge in img: in every column, from just
    // below the wall above the key's top edge (the rows gap..2 gap above it) down, the first row
    // where img differs from that wall (max channel over prah), at most max rows below the key's
    // top. In columns [skip0, skip1) a tap may stand behind the object: a column there counts only
    // if what is above the key's top has the colour of the wall on either side (within prah of
    // the mean wall okno pixels beside the span, interpolated). The edge of a column is the median
    // of the counted columns within okno pixels; the others are interpolated in height between
    // the nearest edges on either side (interpolating the distance below the key's top put
    // Savoy's rim behind the tap 3 px too high, with a strip of wall), and their gap rows from
    // the edge down are solid. Rows above the edge
    // are cut off, rows between it and a lower key filled. Where the column's wall is known, the
    // edge's row and the one above it get the opacity of their colour between that wall and the
    // rim (the most different of the three rows from the edge down): anti-aliasing, and a column
    // whose edge is a pixel off the median gets it back. The median distance of the edge below
    // the key's top goes to presah.
    // In oprav (or null), the object's colour in those rows of the tap's columns (and gap columns
    // beside them), with the edge's anti-aliasing, is interpolated from the columns on either side
    // at the same depth below the edge: the old tap's dark foot on the rim stuck out beside a new
    // tap standing a few pixels elsewhere.
    public static float[] OrezKluc(Obr img, float[] key, int w, int h, int max, int gap, float prah, int skip0, int skip1, int okno, Obr oprav, out int presah)
    {
        const int NIC = int.MinValue;
        var top = new int[w];
        var e = new int[w];
        var wr = new float[w];
        var wg = new float[w];
        var wb = new float[w];
        var wall = new bool[w];
        for (int x = 0; x < w; x++)
        {
            top[x] = -1;
            e[x] = NIC;
            for (int y = 0; y < h; y++) if (key[y * w + x] > 0.5f) { top[x] = y; break; }
            int yk = top[x];
            if (yk < 2 * gap) continue;
            float r = 0, g = 0, b = 0;
            for (int y = yk - 2 * gap; y < yk - gap; y++) { int i = y * w + x; r += img.R[i]; g += img.G[i]; b += img.B[i]; }
            r /= gap; g /= gap; b /= gap;
            wr[x] = r; wg[x] = g; wb[x] = b; wall[x] = true;
            if (x >= skip0 && x < skip1) continue;   // measured once checked below
            for (int y = yk - gap + 1; y <= Math.Min(h - 1, yk + max); y++)
            {
                int i = y * w + x;
                if (Math.Max(Math.Abs(img.R[i] - r), Math.Max(Math.Abs(img.G[i] - g), Math.Abs(img.B[i] - b))) > prah) { e[x] = y - yk; break; }
            }
        }
        if (skip1 > skip0)
        {
            // The wall beside the span; columns inside whose wall is another colour (the tap).
            var side = new double[6];
            int nl = 0, nr = 0;
            for (int x = Math.Max(0, skip0 - okno); x < Math.Min(w, skip1 + okno); x++)
            {
                if ((x >= skip0 && x < skip1) || !wall[x]) continue;
                int k = x < skip0 ? 0 : 3;
                side[k] += wr[x]; side[k + 1] += wg[x]; side[k + 2] += wb[x];
                if (x < skip0) nl++; else nr++;
            }
            for (int x = skip0; x < Math.Min(w, skip1); x++)
            {
                if (!wall[x]) continue;
                if (nl == 0 || nr == 0) { wall[x] = false; continue; }
                double t = (x - skip0 + 0.5) / (skip1 - skip0);
                double sr = side[0] / nl + (side[3] / nr - side[0] / nl) * t, sg = side[1] / nl + (side[4] / nr - side[1] / nl) * t, sb = side[2] / nl + (side[5] / nr - side[2] / nl) * t;
                if (Math.Max(Math.Abs(wr[x] - sr), Math.Max(Math.Abs(wg[x] - sg), Math.Abs(wb[x] - sb))) > prah) { wall[x] = false; continue; }
                int yk = top[x];
                for (int y = yk - gap + 1; y <= Math.Min(h - 1, yk + max); y++)
                {
                    int i = y * w + x;
                    if (Math.Max(Math.Abs(img.R[i] - wr[x]), Math.Max(Math.Abs(img.G[i] - wg[x]), Math.Abs(img.B[i] - wb[x]))) > prah) { e[x] = y - yk; break; }
                }
            }
        }
        // The tap's columns, and gap columns beside them (the old tap's dark foot on the rim).
        var tap = new bool[w];
        for (int x = skip0; x < Math.Min(w, skip1); x++)
        {
            if (wall[x] || top[x] < 0) continue;
            for (int j = Math.Max(0, x - gap); j <= Math.Min(w - 1, x + gap); j++) tap[j] = true;
        }
        for (int x = 0; x < w; x++) if (tap[x]) { e[x] = NIC; wall[x] = false; }
        var es = new float[w];
        var all = new System.Collections.Generic.List<int>();
        for (int x = 0; x < w; x++)
        {
            es[x] = float.NaN;
            if (top[x] < 0 || tap[x]) continue;   // the tap's columns: interpolated
            var win = new System.Collections.Generic.List<int>();
            for (int j = Math.Max(0, x - okno); j <= Math.Min(w - 1, x + okno); j++) if (e[j] != NIC) win.Add(e[j]);
            if (win.Count == 0) continue;
            win.Sort();
            es[x] = win[win.Count / 2];
            all.Add(win[win.Count / 2]);
        }
        all.Sort();
        presah = all.Count > 0 ? all[all.Count / 2] : 0;
        for (int x = 0; x < w; x++)
        {
            if (top[x] < 0 || !float.IsNaN(es[x])) continue;
            int l = x - 1, rr = x + 1;
            while (l >= 0 && float.IsNaN(es[l])) l--;
            while (rr < w && float.IsNaN(es[rr])) rr++;
            if (l >= 0 && rr < w)
            {
                float yl = top[l] + es[l], yr = top[rr] + es[rr];
                es[x] = yl + (yr - yl) * (x - l) / (float)(rr - l) - top[x];
            }
            else if (l >= 0) es[x] = top[l] + es[l] - top[x];
            else if (rr < w) es[x] = top[rr] + es[rr] - top[x];
            else es[x] = 0;
        }
        var o = (float[])key.Clone();
        var edge = new int[w];
        for (int x = 0; x < w; x++)
        {
            edge[x] = -1;
            if (top[x] < 0) continue;
            int y0 = top[x];
            while (y0 > 0 && key[(y0 - 1) * w + x] > 0) y0--;   // the soft edge above the top
            int y1 = Math.Max(1, top[x] + (int)Math.Round(es[x]));
            edge[x] = y1;
            for (int y = Math.Min(y0, y1); y < Math.Max(top[x], y1); y++) o[y * w + x] = y < y1 ? 0f : 1f;
            if (tap[x])
            {
                // The tap's column: the model paints the key only partly over the old tap's foot,
                // the rim there was translucent (the new tap's shadow showed through as grey).
                for (int y = y1; y < Math.Min(h, y1 + gap); y++) o[y * w + x] = 1f;
                edge[x] = -2;
                continue;
            }
            if (!wall[x]) continue;
            float dr = 0, dg = 0, db = 0, best = 0;
            for (int y = y1; y <= Math.Min(h - 1, y1 + 2); y++)
            {
                int i = y * w + x;
                float d = Math.Max(Math.Abs(img.R[i] - wr[x]), Math.Max(Math.Abs(img.G[i] - wg[x]), Math.Abs(img.B[i] - wb[x])));
                if (d > best) { best = d; dr = img.R[i] - wr[x]; dg = img.G[i] - wg[x]; db = img.B[i] - wb[x]; }
            }
            if (best <= prah) continue;
            float d2 = dr * dr + dg * dg + db * db;
            for (int y = y1 - 1; y <= y1; y++)
            {
                int i = y * w + x;
                float pr = ((img.R[i] - wr[x]) * dr + (img.G[i] - wg[x]) * dg + (img.B[i] - wb[x]) * db) / d2;
                o[i] = Math.Min(1f, Math.Max(0f, pr));
            }
        }
        if (oprav != null)
        {
            for (int x = 0; x < w; x++)
            {
                if (edge[x] != -2) continue;
                int l = x - 1, r = x + 1;
                while (l >= 0 && edge[l] == -2) l--;
                while (r < w && edge[r] == -2) r++;
                if (l < 0 || r >= w || edge[l] < 0 || edge[r] < 0) continue;
                int y1 = Math.Max(1, top[x] + (int)Math.Round(es[x]));
                float t = (x - l) / (float)(r - l);
                for (int d = -1; d < gap; d++)   // from the row of the edge's anti-aliasing above it
                {
                    if (y1 + d >= h || edge[l] + d >= h || edge[r] + d >= h) break;
                    int i = (y1 + d) * w + x, il = (edge[l] + d) * w + l, ir = (edge[r] + d) * w + r;
                    oprav.R[i] = oprav.R[il] + (oprav.R[ir] - oprav.R[il]) * t;
                    oprav.G[i] = oprav.G[il] + (oprav.G[ir] - oprav.G[il]) * t;
                    oprav.B[i] = oprav.B[il] + (oprav.B[ir] - oprav.B[il]) * t;
                    if (d <= 0) o[i] = o[il] + (o[ir] - o[il]) * t;
                }
            }
        }
        return o;
    }

    // Thin yellowish parts (the diffuser's reeds on a beige wall): where (R + G) / 2 - B is above
    // its local mean (box blur radius r) by t0..t1. The wall's texture changes mostly in
    // brightness, so it stays out (a difference to another generation catches the texture too).
    public static float[] Tenke(Obr img, int r, float t0, float t1)
    {
        var s = img.Rozmaz(r);
        var o = new float[img.R.Length];
        for (int i = 0; i < o.Length; i++)
        {
            float d = (img.R[i] + img.G[i]) / 2 - img.B[i] - ((s.R[i] + s.G[i]) / 2 - s.B[i]);
            o[i] = Math.Min(1f, Math.Max(0f, (d - t0) / (t1 - t0)));
        }
        return o;
    }

    // Mask moved by (dx, dy) pixels; uncovered pixels are 0.
    public static float[] Posun(float[] m, int w, int h, int dx, int dy)
    {
        var o = new float[m.Length];
        for (int y = Math.Max(0, dy); y < Math.Min(h, h + dy); y++)
            for (int x = Math.Max(0, dx); x < Math.Min(w, w + dx); x++)
                o[y * w + x] = m[(y - dy) * w + x - dx];
        return o;
    }
}

// Finds how a generated image is scaled and shifted against the image it was generated from.
// At 4K the model re-frames the scene slightly (~0.5-1 % zoom, a few pixels of shift), which
// would make layers from different generations not line up.
public static class Zarovnanie
{
    // Gradient magnitude of the luma.
    static float[] Hrany(Obr o)
    {
        int w = o.W, h = o.H;
        var L = new float[w * h];
        for (int i = 0; i < L.Length; i++) L[i] = 0.299f * o.R[i] + 0.587f * o.G[i] + 0.114f * o.B[i];
        var g = new float[w * h];
        for (int y = 1; y < h - 1; y++)
            for (int x = 1; x < w - 1; x++)
            {
                float gx = L[y * w + x + 1] - L[y * w + x - 1], gy = L[(y + 1) * w + x] - L[(y - 1) * w + x];
                g[y * w + x] = (float)Math.Sqrt(gx * gx + gy * gy);
            }
        return g;
    }

    // Normalised correlation of edge map a (reference) with b sampled at (u - c) * s + c + d.
    static double Zhoda(float[] a, float[] b, int w, int h, double sx, double sy, double dx, double dy, int step)
    {
        double sab = 0, saa = 0, sbb = 0;
        int m = w / 40;
        for (int y = m; y < h - m; y += step)
        {
            double by = (y + 0.5 - h / 2.0) * sy + h / 2.0 + dy - 0.5;
            int y0 = (int)Math.Floor(by);
            if (y0 < 0 || y0 + 1 >= h) continue;
            double fy = by - y0;
            for (int x = m; x < w - m; x += step)
            {
                double bx = (x + 0.5 - w / 2.0) * sx + w / 2.0 + dx - 0.5;
                int x0 = (int)Math.Floor(bx);
                if (x0 < 0 || x0 + 1 >= w) continue;
                double fx = bx - x0;
                int p = y0 * w + x0;
                double v = (b[p] * (1 - fx) + b[p + 1] * fx) * (1 - fy) + (b[p + w] * (1 - fx) + b[p + w + 1] * fx) * fy;
                double u = a[y * w + x];
                sab += u * v; saa += u * u; sbb += v * v;
            }
        }
        return sab / Math.Sqrt(saa * sbb + 1e-9);
    }

    // Pattern search from t = {sx, sy, dx, dy} (shift in pixels of this level).
    static double[] Dolad(float[] a, float[] b, int w, int h, double[] t, double ds, double dd, int step)
    {
        var best = (double[])t.Clone();
        double bv = Zhoda(a, b, w, h, best[0], best[1], best[2], best[3], step);
        double[] st = { ds, ds, dd, dd };
        for (int it = 0; it < 300 && st[2] > dd / 16; it++)
        {
            bool moved = false;
            for (int k = 0; k < 4; k++)
                foreach (int sgn in new[] { 1, -1 })
                {
                    var c = (double[])best.Clone();
                    c[k] += sgn * st[k];
                    double v = Zhoda(a, b, w, h, c[0], c[1], c[2], c[3], step);
                    if (v > bv) { bv = v; best = c; moved = true; }
                }
            if (!moved) for (int k = 0; k < 4; k++) st[k] /= 2;
        }
        return best;
    }

    // Returns {sx, sy, dx, dy, correlation}; dx, dy in pixels of the reference (base frame).
    // See Obr.NacitajZarovnane.
    public static double[] Najdi(Obr reference, string path)
    {
        int w = reference.W, h = reference.H, w4 = w / 4, h4 = h / 4, w2 = w / 2, h2 = h / 2;
        var a4 = Hrany(reference.Zmensi(4));
        var b4 = Hrany(Obr.Nacitaj(path, w4, h4, 0));
        double bestV = -1;
        double[] best = null;
        object lk = new object();
        Parallel.For(0, 31, si =>
        {
            double s = 0.97 + si * 0.002, mv = -1;
            double[] mb = null;
            for (int dy = -12; dy <= 12; dy++)
                for (int dx = -12; dx <= 12; dx++)
                {
                    double v = Zhoda(a4, b4, w4, h4, s, s, dx, dy, 3);
                    if (v > mv) { mv = v; mb = new double[] { s, s, dx, dy }; }
                }
            lock (lk) { if (mv > bestV) { bestV = mv; best = mb; } }
        });
        best = Dolad(a4, b4, w4, h4, best, 0.001, 0.5, 2);
        var a2 = Hrany(reference.Zmensi(2));
        var b2 = Hrany(Obr.Nacitaj(path, w2, h2, 0));
        best = Dolad(a2, b2, w2, h2, new double[] { best[0], best[1], best[2] * 2, best[3] * 2 }, 0.0005, 0.5, 2);
        double q = Zhoda(a2, b2, w2, h2, best[0], best[1], best[2], best[3], 2);
        return new double[] { best[0], best[1], best[2] * 2, best[3] * 2, q };
    }

    // Best integer shift (dx, dy) of edge map b against a inside box [x0, x1) x [y0, y1),
    // b(u + d) ~ a(u), searched in [c - r, c + r] around the centre c.
    static int[] NajlepsiPosun(float[] a, float[] b, int w, int h, int x0, int y0, int x1, int y1, int cx, int cy, int r, int step)
    {
        double bestV = -1;
        int[] best = { cx, cy };
        object lk = new object();
        Parallel.For(-r, r + 1, oy =>
        {
            int dy = cy + oy;
            double mv = -1; int mx = cx;
            for (int dx = cx - r; dx <= cx + r; dx++)
            {
                double sab = 0, saa = 0, sbb = 0;
                for (int y = y0; y < y1; y += step)
                {
                    int by = y + dy;
                    if (by < 0 || by >= h) continue;
                    for (int x = x0; x < x1; x += step)
                    {
                        int bx = x + dx;
                        if (bx < 0 || bx >= w) continue;
                        double u = a[y * w + x], v = b[by * w + bx];
                        sab += u * v; saa += u * u; sbb += v * v;
                    }
                }
                double c = sab / Math.Sqrt(saa * sbb + 1e-9);
                if (c > mv) { mv = c; mx = dx; }
            }
            lock (lk) { if (mv > bestV || (mv == bestV && Math.Abs(dy) < Math.Abs(best[1]))) { bestV = mv; best = new[] { mx, dy }; } }
        });
        return best;
    }

    // Local correction inside each ROI rectangle (normalised x0, y0, x1, y1 quads): the model
    // sometimes moves a part of the scene by a few pixels even when the whole frame matches.
    // Returns dx, dy per rectangle (pixels); see Obr.Posun.
    public static int[] Posuny(Obr reference, Obr img, double[] quads, int range)
    {
        int w = reference.W, h = reference.H, w2 = w / 2, h2 = h / 2;
        var a2 = Hrany(reference.Zmensi(2)); var b2 = Hrany(img.Zmensi(2));
        var a1 = Hrany(reference); var b1 = Hrany(img);
        var d = new int[quads.Length / 2];
        for (int q = 0; q + 3 < quads.Length; q += 4)
        {
            // the rectangle plus a margin, for context edges around the object
            double mx = 0.03, my = 0.03;
            int x0 = (int)(Math.Max(0, quads[q] - mx) * w), y0 = (int)(Math.Max(0, quads[q + 1] - my) * h);
            int x1 = (int)(Math.Min(1, quads[q + 2] + mx) * w), y1 = (int)(Math.Min(1, quads[q + 3] + my) * h);
            var c = NajlepsiPosun(a2, b2, w2, h2, x0 / 2, y0 / 2, x1 / 2, y1 / 2, 0, 0, range / 2, 1);
            var f = NajlepsiPosun(a1, b1, w, h, x0, y0, x1, y1, c[0] * 2, c[1] * 2, 2, 2);
            d[q / 2] = f[0]; d[q / 2 + 1] = f[1];
        }
        return d;
    }
}
