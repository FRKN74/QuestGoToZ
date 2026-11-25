using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace QuestGoToZTranslatorApp
{
    static class Program
    {
        [DllImport("user32.dll")]
        private static extern bool SetProcessDPIAware();

        [STAThread]
        static void Main()
        {
            bool createdNew;
            using (Mutex mutex = new Mutex(true, "QuestGoToZ_Translator_SingleInstance", out createdNew))
            {
                if (!createdNew)
                {
                    MessageBox.Show("QuestGoToZ Translator zaten arka planda calisiyor (sistem tepsisini kontrol edin).",
                        "QuestGoToZ Translator", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
                try { SetProcessDPIAware(); } catch { }
                try { ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072 | SecurityProtocolType.Tls12; } catch { }
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new TranslatorForm());
            }
        }
    }

    public class TranslatorForm : Form
    {
        private const int WM_HOTKEY = 0x0312;
        private const int HOTKEY_ID = 9001;

        private const uint MOD_ALT = 0x0001;
        private const uint MOD_CONTROL = 0x0002;
        private const uint MOD_SHIFT = 0x0004;
        private const uint MOD_NOREPEAT = 0x4000;

        private const byte VK_CONTROL = 0x11;
        private const byte VK_MENU = 0x12; // Alt
        private const byte VK_SHIFT = 0x10;
        private const byte VK_RETURN = 0x0D;
        private const byte VK_A = 0x41;
        private const byte VK_C = 0x43;
        private const byte VK_V = 0x56;
        private const byte VK_T = 0x54;
        private const byte VK_F9 = 0x78;

        private const uint KEYEVENTF_KEYUP = 0x0002;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        [DllImport("user32.dll")]
        private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

        [DllImport("user32.dll")]
        private static extern uint MapVirtualKey(uint uCode, uint uMapType);

        [DllImport("user32.dll")]
        private static extern short GetAsyncKeyState(int vKey);

        // Koyu WoW / Midnight temasi
        private readonly Color colBg = Color.FromArgb(17, 20, 29);
        private readonly Color colCard = Color.FromArgb(25, 30, 44);
        private readonly Color colBorder = Color.FromArgb(40, 48, 70);
        private readonly Color colInput = Color.FromArgb(14, 17, 24);
        private readonly Color colText = Color.FromArgb(230, 234, 242);
        private readonly Color colMuted = Color.FromArgb(142, 153, 179);
        private readonly Color colGold = Color.FromArgb(240, 180, 41);
        private readonly Color colGoldHover = Color.FromArgb(247, 199, 82);
        private readonly Color colGreen = Color.FromArgb(34, 197, 94);
        private readonly Color colGreenBg = Color.FromArgb(19, 42, 30);
        private readonly Color colRed = Color.FromArgb(239, 68, 68);
        private readonly Color colRedBg = Color.FromArgb(45, 21, 25);
        private readonly Color colBtn = Color.FromArgb(38, 46, 66);
        private readonly Color colBtnHover = Color.FromArgb(50, 60, 86);

        private Label lblBadge;
        private CheckBox chkEnabled;
        private CheckBox chkAutoEnter;
        private ComboBox cmbHotkey;
        private TextBox txtTestInput;
        private TextBox txtTestOutput;
        private RichTextBox rtbLog;
        private NotifyIcon trayIcon;

        private bool isTranslating = false;
        private bool forceExit = false;

        public TranslatorForm()
        {
            BuildUI();
            InitTray();
            ApplySelectedHotkey();
        }

        private void BuildUI()
        {
            this.Text = "QuestGoToZ Translator — TR -> EN (Canli Ceviri)";
            this.Size = new Size(620, 500);
            this.MinimumSize = new Size(560, 460);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = colBg;
            this.ForeColor = colText;
            this.Font = new Font("Segoe UI", 9F);

            Panel top = new Panel { Dock = DockStyle.Top, Height = 64, BackColor = colBg };
            this.Controls.Add(top);

            Label lblTitle = new Label
            {
                Text = "QuestGoToZ Canli Cevirmen (TR -> EN)",
                Font = new Font("Segoe UI", 13.5F, FontStyle.Bold),
                ForeColor = colGold,
                AutoSize = true,
                Location = new Point(16, 10)
            };
            top.Controls.Add(lblTitle);

            Label lblSub = new Label
            {
                Text = "WoW sohbetine Turkce yaz -> Kisayola bas -> %100 gercek Ingilizce cevirisi aninda yapissin",
                Font = new Font("Segoe UI", 8.5F),
                ForeColor = colMuted,
                AutoSize = true,
                Location = new Point(18, 37)
            };
            top.Controls.Add(lblSub);

            lblBadge = new Label
            {
                Text = "● Aktif (Alt+T)",
                Font = new Font("Segoe UI", 9F, FontStyle.Bold),
                ForeColor = colGreen,
                BackColor = colGreenBg,
                AutoSize = true,
                Padding = new Padding(10, 5, 10, 5),
                Anchor = AnchorStyles.Top | AnchorStyles.Right,
                Location = new Point(470, 16)
            };
            top.Controls.Add(lblBadge);

            TableLayoutPanel root = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                Padding = new Padding(16, 4, 16, 14),
                ColumnCount = 1,
                RowCount = 3,
                BackColor = colBg
            };
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 108F));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 126F));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            this.Controls.Add(root);
            root.BringToFront();

            // Kart 1: Ayarlar
            Panel c1 = CreateCard("1. Kisayol ve Calisma Ayarlari");
            c1.Dock = DockStyle.Fill;
            c1.Margin = new Padding(0, 0, 0, 10);
            root.Controls.Add(c1, 0, 0);
            Panel b1 = (Panel)c1.Tag;

            chkEnabled = new CheckBox
            {
                Text = "Cevirmen Aktif",
                Checked = true,
                AutoSize = true,
                ForeColor = colText,
                Location = new Point(4, 6)
            };
            chkEnabled.CheckedChanged += delegate { UpdateStatusBadge(); };
            b1.Controls.Add(chkEnabled);

            chkAutoEnter = new CheckBox
            {
                Text = "Cevirince otomatik Enter'a bas (hemen gonder)",
                Checked = false,
                AutoSize = true,
                ForeColor = colText,
                Location = new Point(150, 6)
            };
            b1.Controls.Add(chkAutoEnter);

            Label lblHk = new Label
            {
                Text = "Ceviri Kisayolu:",
                AutoSize = true,
                ForeColor = colMuted,
                Location = new Point(4, 38)
            };
            b1.Controls.Add(lblHk);

            cmbHotkey = new ComboBox
            {
                DropDownStyle = ComboBoxStyle.DropDownList,
                BackColor = colInput,
                ForeColor = colText,
                Width = 150,
                Location = new Point(108, 34)
            };
            cmbHotkey.Items.AddRange(new object[] { "Alt + T", "F9", "Ctrl + Shift + T" });
            cmbHotkey.SelectedIndex = 0;
            cmbHotkey.SelectedIndexChanged += delegate { ApplySelectedHotkey(); };
            b1.Controls.Add(cmbHotkey);

            Button btnHide = CreateButton("Arka Plana Al", colBtn, colBtnHover, colText);
            btnHide.Size = new Size(120, 26);
            btnHide.Location = new Point(280, 32);
            btnHide.Click += delegate { MinimizeToTray(); };
            b1.Controls.Add(btnHide);

            // Kart 2: Hizli Test
            Panel c2 = CreateCard("2. Hizli Ceviri Testi (TR -> EN)");
            c2.Dock = DockStyle.Fill;
            c2.Margin = new Padding(0, 0, 0, 10);
            root.Controls.Add(c2, 0, 1);
            Panel b2 = (Panel)c2.Tag;

            txtTestInput = new TextBox
            {
                BackColor = colInput,
                ForeColor = colText,
                BorderStyle = BorderStyle.FixedSingle,
                Font = new Font("Segoe UI", 9.5F),
                Location = new Point(4, 6),
                Width = 430,
                Text = "Beyler soldaki moblari atlayip direkt bossa gidelim, manam dolunca cekecegim"
            };
            b2.Controls.Add(txtTestInput);

            Button btnTest = CreateButton("Cevir", colGold, colGoldHover, colBg);
            btnTest.Size = new Size(96, 26);
            btnTest.Location = new Point(444, 5);
            btnTest.Click += delegate { RunManualTest(); };
            b2.Controls.Add(btnTest);

            txtTestOutput = new TextBox
            {
                BackColor = colInput,
                ForeColor = colGreen,
                BorderStyle = BorderStyle.FixedSingle,
                ReadOnly = true,
                Font = new Font("Segoe UI", 9.5F),
                Location = new Point(4, 42),
                Width = 536
            };
            b2.Controls.Add(txtTestOutput);

            // Kart 3: Gecmis
            Panel c3 = CreateCard("3. Son Ceviriler");
            c3.Dock = DockStyle.Fill;
            root.Controls.Add(c3, 0, 2);
            Panel b3 = (Panel)c3.Tag;

            rtbLog = new RichTextBox
            {
                Dock = DockStyle.Fill,
                BackColor = colInput,
                ForeColor = colText,
                BorderStyle = BorderStyle.None,
                ReadOnly = true,
                Font = new Font("Consolas", 9F)
            };
            b3.Controls.Add(rtbLog);

            Log("Hazir! WoW sohbet kutusuna Turkce yazip 'Alt + T' tusuna basin.", colGreen);
        }

        private Panel CreateCard(string title)
        {
            Panel card = new Panel { BackColor = colCard, Padding = new Padding(12, 8, 12, 10) };
            card.Paint += delegate(object s, PaintEventArgs e)
            {
                using (Pen pen = new Pen(colBorder))
                {
                    e.Graphics.DrawRectangle(pen, 0, 0, card.Width - 1, card.Height - 1);
                }
            };

            Label hdr = new Label
            {
                Text = title,
                Font = new Font("Segoe UI", 9F, FontStyle.Bold),
                ForeColor = colGold,
                Dock = DockStyle.Top,
                Height = 22
            };
            card.Controls.Add(hdr);

            Panel body = new Panel { Dock = DockStyle.Fill, BackColor = colCard };
            card.Controls.Add(body);
            body.BringToFront();
            card.Tag = body;
            return card;
        }

        private Button CreateButton(string text, Color bg, Color hover, Color fg)
        {
            Button btn = new Button
            {
                Text = text,
                FlatStyle = FlatStyle.Flat,
                BackColor = bg,
                ForeColor = fg,
                Font = new Font("Segoe UI", 9F, FontStyle.Bold),
                Cursor = Cursors.Hand
            };
            btn.FlatAppearance.BorderSize = 0;
            btn.MouseEnter += delegate { btn.BackColor = hover; };
            btn.MouseLeave += delegate { btn.BackColor = bg; };
            return btn;
        }

        private void InitTray()
        {
            ContextMenu menu = new ContextMenu();
            menu.MenuItems.Add("Pencereyi Ac", delegate { RestoreFromTray(); });
            menu.MenuItems.Add("Cikis", delegate
            {
                forceExit = true;
                trayIcon.Visible = false;
                Application.Exit();
            });

            trayIcon = new NotifyIcon
            {
                Icon = SystemIcons.Application,
                Text = "QuestGoToZ Translator (TR -> EN)",
                Visible = true,
                ContextMenu = menu
            };
            trayIcon.DoubleClick += delegate { RestoreFromTray(); };
        }

        private void MinimizeToTray()
        {
            this.Hide();
            trayIcon.ShowBalloonTip(1800, "QuestGoToZ Translator",
                "Arka planda calisiyor. WoW sohbetinde " + cmbHotkey.Text + " ile cevirebilirsiniz.",
                ToolTipIcon.Info);
        }

        private void RestoreFromTray()
        {
            this.Show();
            this.WindowState = FormWindowState.Normal;
            this.Activate();
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (!forceExit && e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                MinimizeToTray();
                return;
            }
            try { UnregisterHotKey(this.Handle, HOTKEY_ID); } catch { }
            if (trayIcon != null) trayIcon.Visible = false;
            base.OnFormClosing(e);
        }

        private void ApplySelectedHotkey()
        {
            try { UnregisterHotKey(this.Handle, HOTKEY_ID); } catch { }
            uint mod = MOD_ALT | MOD_NOREPEAT;
            uint vk = VK_T;
            int idx = cmbHotkey.SelectedIndex;
            if (idx == 1)
            {
                mod = MOD_NOREPEAT;
                vk = VK_F9;
            }
            else if (idx == 2)
            {
                mod = MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT;
                vk = VK_T;
            }

            bool ok = RegisterHotKey(this.Handle, HOTKEY_ID, mod, vk);
            if (!ok)
            {
                Log("Uyari: " + cmbHotkey.Text + " kisayolu baska programda kullanimda, baska tus secin.", colRed);
            }
            else
            {
                Log("Kisayol ayarlandi: " + cmbHotkey.Text, colMuted);
            }
            UpdateStatusBadge();
        }

        private void UpdateStatusBadge()
        {
            if (chkEnabled.Checked)
            {
                lblBadge.Text = "● Aktif (" + cmbHotkey.Text + ")";
                lblBadge.ForeColor = colGreen;
                lblBadge.BackColor = colGreenBg;
            }
            else
            {
                lblBadge.Text = "○ Duraklatildi";
                lblBadge.ForeColor = colRed;
                lblBadge.BackColor = colRedBg;
            }
            lblBadge.Location = new Point(this.ClientSize.Width - lblBadge.Width - 18, 16);
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == HOTKEY_ID)
            {
                if (chkEnabled.Checked && !isTranslating)
                {
                    TriggerLiveTranslate();
                }
            }
            base.WndProc(ref m);
        }

        private void PressKey(byte vk, bool keyUp)
        {
            byte scan = (byte)MapVirtualKey(vk, 0);
            keybd_event(vk, scan, keyUp ? KEYEVENTF_KEYUP : 0, UIntPtr.Zero);
        }

        private void WaitForModifiersReleased()
        {
            for (int i = 0; i < 30; i++)
            {
                bool altDown = (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
                bool ctrlDown = (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
                bool shiftDown = (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;
                if (!altDown && !ctrlDown && !shiftDown) break;
                Thread.Sleep(25);
            }
            PressKey(VK_MENU, true);
            PressKey(VK_SHIFT, true);
            PressKey(VK_CONTROL, true);
            Thread.Sleep(40);
        }

        private void SendCtrlKey(byte vk)
        {
            PressKey(VK_CONTROL, false);
            Thread.Sleep(35);
            PressKey(vk, false);
            Thread.Sleep(45);
            PressKey(vk, true);
            Thread.Sleep(35);
            PressKey(VK_CONTROL, true);
            Thread.Sleep(30);
        }

        private void SendEnterKey()
        {
            PressKey(VK_RETURN, false);
            Thread.Sleep(35);
            PressKey(VK_RETURN, true);
        }

        private string GetClipboardTextSafe()
        {
            string res = null;
            for (int attempt = 0; attempt < 5; attempt++)
            {
                bool ok = false;
                this.Invoke((MethodInvoker)delegate
                {
                    try
                    {
                        if (Clipboard.ContainsText())
                            res = Clipboard.GetText();
                        ok = true;
                    }
                    catch { }
                });
                if (ok) return res;
                Thread.Sleep(30);
            }
            return res;
        }

        private bool SetClipboardTextSafe(string text)
        {
            for (int attempt = 0; attempt < 8; attempt++)
            {
                bool ok = false;
                this.Invoke((MethodInvoker)delegate
                {
                    try
                    {
                        if (text == null) Clipboard.Clear();
                        else Clipboard.SetText(text, TextDataFormat.UnicodeText);
                        ok = true;
                    }
                    catch { }
                });
                if (ok) return true;
                Thread.Sleep(35);
            }
            return false;
        }

        private void TriggerLiveTranslate()
        {
            isTranslating = true;
            bool autoEnter = chkAutoEnter.Checked;

            ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    WaitForModifiersReleased();

                    string marker = "__QGT_EMPTY_" + Guid.NewGuid().ToString("N") + "__";
                    SetClipboardTextSafe(marker);
                    Thread.Sleep(40);

                    // 1) Aktif sohbet kutusundaki metni sec ve kopyala
                    SendCtrlKey(VK_A);
                    Thread.Sleep(60);
                    SendCtrlKey(VK_C);

                    // 2) WoW'un panoyu doldurmasini bekle (maks 500ms)
                    string copied = null;
                    for (int w = 0; w < 25; w++)
                    {
                        Thread.Sleep(20);
                        string cur = GetClipboardTextSafe();
                        if (!string.IsNullOrEmpty(cur) && cur != marker)
                        {
                            copied = cur;
                            break;
                        }
                    }

                    if (string.IsNullOrWhiteSpace(copied))
                    {
                        SafeLog("Sohbet kutusundan metin kopyalanamadi (kutu aktif mi?).", colMuted);
                        return;
                    }

                    if (copied.TrimStart().StartsWith("/"))
                    {
                        SafeLog("Komut atlandi: " + copied, colMuted);
                        return;
                    }

                    // 3) Gercek Google Translate ile cevir
                    string translated = TranslateTrToEn(copied);
                    if (string.IsNullOrWhiteSpace(translated))
                    {
                        SafeLog("Ceviri alinamadi (internet baglantisini kontrol edin).", colRed);
                        return;
                    }

                    // 4) Cevrilen metni panoya yaz ve sohbet kutusuna yapistir
                    if (!SetClipboardTextSafe(translated))
                    {
                        SafeLog("Pano yazilamadi, tekrar deneyin.", colRed);
                        return;
                    }
                    Thread.Sleep(60);
                    SendCtrlKey(VK_A);
                    Thread.Sleep(50);
                    SendCtrlKey(VK_V);

                    if (autoEnter)
                    {
                        Thread.Sleep(80);
                        SendEnterKey();
                    }

                    SafeLog("TR: " + copied + "\nEN: " + translated, colGreen);
                }
                catch (Exception ex)
                {
                    SafeLog("Hata: " + ex.Message, colRed);
                }
                finally
                {
                    isTranslating = false;
                }
            });
        }

        private void RunManualTest()
        {
            string src = txtTestInput.Text.Trim();
            if (string.IsNullOrEmpty(src)) return;
            txtTestOutput.Text = "Ceviriliyor...";
            ThreadPool.QueueUserWorkItem(delegate
            {
                string en = TranslateTrToEn(src);
                this.BeginInvoke((MethodInvoker)delegate
                {
                    txtTestOutput.Text = string.IsNullOrEmpty(en) ? "Hata: Ceviri alinamadi." : en;
                    if (!string.IsNullOrEmpty(en))
                    {
                        Log("TEST TR: " + src + "\nTEST EN: " + en, colGreen);
                    }
                });
            });
        }

        private string TranslateTrToEn(string text)
        {
            // 1) Google Translate ucretsiz resmi gtx uc noktasi
            try
            {
                string url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=tr&tl=en&dt=t&q="
                    + Uri.EscapeDataString(text);
                using (WebClient wc = new WebClient())
                {
                    wc.Encoding = Encoding.UTF8;
                    wc.Headers.Add("User-Agent", "Mozilla/5.0");
                    string json = wc.DownloadString(url);
                    string parsed = ParseGoogleTranslateJson(json);
                    if (!string.IsNullOrWhiteSpace(parsed))
                        return parsed;
                }
            }
            catch { }

            // 2) Yedek: MyMemory ucretsiz API
            try
            {
                string url2 = "https://api.mymemory.translated.net/get?q="
                    + Uri.EscapeDataString(text) + "&langpair=tr|en";
                using (WebClient wc = new WebClient())
                {
                    wc.Encoding = Encoding.UTF8;
                    string json2 = wc.DownloadString(url2);
                    int idx = json2.IndexOf("\"translatedText\":\"", StringComparison.OrdinalIgnoreCase);
                    if (idx >= 0)
                    {
                        int pos = idx + "\"translatedText\":\"".Length;
                        return ReadJsonString(json2, ref pos);
                    }
                }
            }
            catch { }

            return null;
        }

        // [[["translated1","orig1",...],["translated2","orig2",...]],...] yapisini eksiksiz cozer
        private string ParseGoogleTranslateJson(string json)
        {
            if (string.IsNullOrEmpty(json)) return null;
            int i = 0;
            int n = json.Length;
            while (i < n && json[i] != '[') i++;
            if (i >= n) return null;
            i++; // outer [
            while (i < n && char.IsWhiteSpace(json[i])) i++;
            if (i >= n || json[i] != '[') return null;
            i++; // sentence list [

            StringBuilder sb = new StringBuilder();
            while (i < n)
            {
                while (i < n && (char.IsWhiteSpace(json[i]) || json[i] == ',')) i++;
                if (i >= n || json[i] == ']') break;
                if (json[i] == '[')
                {
                    i++;
                    while (i < n && char.IsWhiteSpace(json[i])) i++;
                    if (i < n && json[i] == '"')
                    {
                        i++;
                        string part = ReadJsonString(json, ref i);
                        if (part != null) sb.Append(part);
                    }
                    // Bu alt dizinin kapanisina kadar ilerle
                    int depth = 1;
                    bool inStr = false;
                    while (i < n && depth > 0)
                    {
                        char c = json[i++];
                        if (inStr)
                        {
                            if (c == '\\' && i < n) i++;
                            else if (c == '"') inStr = false;
                        }
                        else
                        {
                            if (c == '"') inStr = true;
                            else if (c == '[') depth++;
                            else if (c == ']') depth--;
                        }
                    }
                }
                else
                {
                    break;
                }
            }
            return sb.ToString().Trim();
        }

        private string ReadJsonString(string s, ref int i)
        {
            StringBuilder sb = new StringBuilder();
            int n = s.Length;
            while (i < n)
            {
                char c = s[i++];
                if (c == '"') return sb.ToString();
                if (c == '\\' && i < n)
                {
                    char esc = s[i++];
                    if (esc == '"') sb.Append('"');
                    else if (esc == '\\') sb.Append('\\');
                    else if (esc == '/') sb.Append('/');
                    else if (esc == 'n') sb.Append(' ');
                    else if (esc == 'r') { }
                    else if (esc == 't') sb.Append(' ');
                    else if (esc == 'u' && i + 4 <= n)
                    {
                        string hex = s.Substring(i, 4);
                        int code;
                        if (int.TryParse(hex, System.Globalization.NumberStyles.HexNumber, null, out code))
                            sb.Append((char)code);
                        i += 4;
                    }
                }
                else
                {
                    sb.Append(c);
                }
            }
            return sb.ToString();
        }

        private void SafeLog(string msg, Color color)
        {
            if (this.IsHandleCreated)
            {
                this.BeginInvoke((MethodInvoker)delegate { Log(msg, color); });
            }
        }

        private void Log(string msg, Color color)
        {
            rtbLog.SelectionStart = rtbLog.TextLength;
            rtbLog.SelectionColor = colMuted;
            rtbLog.AppendText("[" + DateTime.Now.ToString("HH:mm:ss") + "] ");
            rtbLog.SelectionColor = color;
            rtbLog.AppendText(msg + Environment.NewLine + Environment.NewLine);
            rtbLog.ScrollToCaret();
        }
    }
}
