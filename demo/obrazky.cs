// Image helpers for zostav.ps1 (compiled by Add-Type; C# 5, System.Drawing only).
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

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

    // Grey image of a mask (for debugging).
    public static Obr ZMasky(float[] a, int w, int h)
    {
        var o = new Obr(w, h);
        for (int i = 0; i < a.Length; i++) { o.R[i] = o.G[i] = o.B[i] = a[i] * 255f; }
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

    // mode 0 = mean, 1 = max, -1 = min over a 1-D window of radius r.
    static float[] Smer(float[] m, int w, int h, int r, bool horiz, int mode)
    {
        var o = new float[m.Length];
        int n = horiz ? w : h, lines = horiz ? h : w;
        for (int l = 0; l < lines; l++)
            for (int k = 0; k < n; k++)
            {
                float acc = mode == 0 ? 0 : m[horiz ? l * w + k : k * w + l];
                int cnt = 0;
                for (int j = Math.Max(0, k - r); j <= Math.Min(n - 1, k + r); j++)
                {
                    float v = m[horiz ? l * w + j : j * w + l];
                    if (mode == 0) acc += v;
                    else if (mode > 0) { if (v > acc) acc = v; }
                    else { if (v < acc) acc = v; }
                    cnt++;
                }
                o[horiz ? l * w + k : k * w + l] = mode == 0 ? acc / cnt : acc;
            }
        return o;
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
