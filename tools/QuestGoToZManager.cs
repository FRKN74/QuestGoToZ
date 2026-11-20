using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace QuestGoToZManagerApp
{
    static class Program
    {
        [DllImport("user32.dll")]
        private static extern bool SetProcessDPIAware();

        [STAThread]
        static void Main()
        {
            try { SetProcessDPIAware(); } catch { }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }

    public class MainForm : Form
    {
        private const string AddonName = "QuestGoToZ";

        private readonly string projectDir;
        private readonly string toolsDir;
        private readonly string configPath;
        private readonly string tocPath;
        private readonly string buildsDir;

        // Tema renkleri
        private readonly Color colBg = Color.FromArgb(17, 20, 29);
        private readonly Color colCard = Color.FromArgb(25, 30, 44);
        private readonly Color colBorder = Color.FromArgb(40, 48, 70);
        private readonly Color colInput = Color.FromArgb(14, 17, 24);
        private readonly Color colText = Color.FromArgb(230, 234, 242);
        private readonly Color colMuted = Color.FromArgb(142, 153, 179);
        private readonly Color colGold = Color.FromArgb(240, 180, 41);
        private readonly Color colGoldHover = Color.FromArgb(247, 199, 82);
        private readonly Color colBlue = Color.FromArgb(59, 130, 246);
        private readonly Color colBlueHover = Color.FromArgb(96, 165, 250);
        private readonly Color colGreen = Color.FromArgb(34, 197, 94);
        private readonly Color colGreenBg = Color.FromArgb(19, 42, 30);
        private readonly Color colYellow = Color.FromArgb(234, 179, 8);
        private readonly Color colYellowBg = Color.FromArgb(43, 36, 17);
        private readonly Color colRed = Color.FromArgb(239, 68, 68);
        private readonly Color colRedBg = Color.FromArgb(45, 21, 25);
        private readonly Color colBtn = Color.FromArgb(38, 46, 66);
        private readonly Color colBtnHover = Color.FromArgb(50, 60, 86);

        // UI kontrolleri
        private Label lblStatusBadge;
        private TextBox txtWowPath;
        private Label lblTargetPreview;
        private ListView lvFiles;
        private TextBox txtInterface;
        private TextBox txtVersion;
        private RichTextBox rtbLog;

        public MainForm()
        {
            string exeDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
            if (File.Exists(Path.Combine(exeDir, AddonName + ".toc")))
            {
                projectDir = exeDir;
            }
            else
            {
                DirectoryInfo parent = Directory.GetParent(exeDir);
                projectDir = (parent != null && File.Exists(Path.Combine(parent.FullName, AddonName + ".toc")))
                    ? parent.FullName
                    : exeDir;
            }

            toolsDir = Path.Combine(projectDir, "tools");
            configPath = Path.Combine(toolsDir, "manager.cfg");
            tocPath = Path.Combine(projectDir, AddonName + ".toc");
            buildsDir = Path.Combine(toolsDir, "builds");

            BuildUI();
            LoadConfig();
            RefreshAll();
            Log("QuestGoToZ Yöneticisi hazır. Proje dizini: " + projectDir, colMuted);
        }

        private void BuildUI()
        {
            this.Text = AddonName + " — Masaüstü Addon Yöneticisi";
            this.Size = new Size(960, 760);
            this.MinimumSize = new Size(900, 700);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = colBg;
            this.ForeColor = colText;
            this.Font = new Font("Segoe UI", 9F, FontStyle.Regular);

            // Ust baslik alani
            Panel topPanel = new Panel();
            topPanel.Dock = DockStyle.Top;
            topPanel.Height = 68;
            topPanel.Padding = new Padding(18, 12, 18, 6);
            topPanel.BackColor = colBg;
            this.Controls.Add(topPanel);

            Label lblTitle = new Label();
            lblTitle.Text = AddonName + " Addon Yöneticisi";
            lblTitle.Font = new Font("Segoe UI", 15F, FontStyle.Bold);
            lblTitle.ForeColor = colGold;
            lblTitle.AutoSize = true;
            lblTitle.Location = new Point(18, 10);
            topPanel.Controls.Add(lblTitle);

            Label lblSub = new Label();
            lblSub.Text = "Proje Dizini: " + projectDir;
            lblSub.Font = new Font("Segoe UI", 8.5F, FontStyle.Regular);
            lblSub.ForeColor = colMuted;
            lblSub.AutoSize = true;
            lblSub.Location = new Point(20, 40);
            topPanel.Controls.Add(lblSub);

            lblStatusBadge = new Label();
            lblStatusBadge.Text = "Durum kontrol ediliyor...";
            lblStatusBadge.Font = new Font("Segoe UI", 9.5F, FontStyle.Bold);
            lblStatusBadge.AutoSize = true;
            lblStatusBadge.Padding = new Padding(12, 6, 12, 6);
            lblStatusBadge.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            lblStatusBadge.Location = new Point(700, 18);
            topPanel.Controls.Add(lblStatusBadge);

            // Ana icerik kapsayicisi
            TableLayoutPanel root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.Padding = new Padding(18, 4, 18, 14);
            root.ColumnCount = 1;
            root.RowCount = 3;
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 148F));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 165F));
            root.BackColor = colBg;
            this.Controls.Add(root);
            root.BringToFront();

            // 1) WoW Kurulum ve Baglanti Karti
            Panel card1 = CreateCard("1. WoW: Forever Kurulum Klasörü ve Bağlantı");
            card1.Dock = DockStyle.Fill;
            card1.Margin = new Padding(0, 0, 0, 10);
            root.Controls.Add(card1, 0, 0);

            Panel c1Body = (Panel)card1.Tag;

            TableLayoutPanel pathRow = new TableLayoutPanel();
            pathRow.Dock = DockStyle.Top;
            pathRow.Height = 32;
            pathRow.ColumnCount = 4;
            pathRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            pathRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 92F));
            pathRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 118F));
            pathRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 82F));
            c1Body.Controls.Add(pathRow);

            txtWowPath = CreateTextBox();
            txtWowPath.Dock = DockStyle.Fill;
            txtWowPath.Margin = new Padding(0, 2, 8, 2);
            txtWowPath.Leave += delegate { SaveConfig(); RefreshStatus(); };
            pathRow.Controls.Add(txtWowPath, 0, 0);

            Button btnBrowse = CreateButton("Gözat...", colBtn, colBtnHover, colText);
            btnBrowse.Dock = DockStyle.Fill;
            btnBrowse.Margin = new Padding(0, 0, 6, 0);
            btnBrowse.Click += delegate { BrowseWowFolder(); };
            pathRow.Controls.Add(btnBrowse, 1, 0);

            Button btnAuto = CreateButton("Otomatik Ara", colBtn, colBtnHover, colText);
            btnAuto.Dock = DockStyle.Fill;
            btnAuto.Margin = new Padding(0, 0, 6, 0);
            btnAuto.Click += delegate { AutoDetectWow(); };
            pathRow.Controls.Add(btnAuto, 2, 0);

            Button btnRefresh = CreateButton("Yenile", colBtn, colBtnHover, colText);
            btnRefresh.Dock = DockStyle.Fill;
            btnRefresh.Click += delegate { RefreshAll(); Log("Durum yenilendi.", colMuted); };
            pathRow.Controls.Add(btnRefresh, 3, 0);

            lblTargetPreview = new Label();
            lblTargetPreview.Text = "Hedef: Geçerli bir WoW klasörü seçin";
            lblTargetPreview.Font = new Font("Consolas", 8.5F);
            lblTargetPreview.ForeColor = colMuted;
            lblTargetPreview.Dock = DockStyle.Top;
            lblTargetPreview.Height = 22;
            lblTargetPreview.Padding = new Padding(0, 4, 0, 0);
            c1Body.Controls.Add(lblTargetPreview);
            lblTargetPreview.BringToFront();

            FlowLayoutPanel actionRow = new FlowLayoutPanel();
            actionRow.Dock = DockStyle.Bottom;
            actionRow.Height = 36;
            actionRow.FlowDirection = FlowDirection.LeftToRight;
            actionRow.WrapContents = false;
            c1Body.Controls.Add(actionRow);

            Button btnJunction = CreateButton("Junction ile Bağla (Önerilen)", colGold, colGoldHover, Color.FromArgb(17, 20, 29));
            btnJunction.Width = 215;
            btnJunction.Height = 32;
            btnJunction.Margin = new Padding(0, 0, 8, 0);
            btnJunction.Click += delegate { ActionCreateJunction(); };
            actionRow.Controls.Add(btnJunction);

            Button btnCopy = CreateButton("Dosyaları Kopyala / Güncelle", colBlue, colBlueHover, Color.White);
            btnCopy.Width = 210;
            btnCopy.Height = 32;
            btnCopy.Margin = new Padding(0, 0, 8, 0);
            btnCopy.Click += delegate { ActionCopyFiles(); };
            actionRow.Controls.Add(btnCopy);

            Button btnUninstall = CreateButton("Kurulumu Kaldır", Color.FromArgb(127, 29, 29), Color.FromArgb(153, 27, 27), Color.White);
            btnUninstall.Width = 135;
            btnUninstall.Height = 32;
            btnUninstall.Margin = new Padding(0, 0, 14, 0);
            btnUninstall.Click += delegate { ActionUninstall(); };
            actionRow.Controls.Add(btnUninstall);

            Button btnOpenProj = CreateButton("Proje Klasörü", colBtn, colBtnHover, colText);
            btnOpenProj.Width = 115;
            btnOpenProj.Height = 32;
            btnOpenProj.Margin = new Padding(0, 0, 6, 0);
            btnOpenProj.Click += delegate { OpenInExplorer(projectDir); };
            actionRow.Controls.Add(btnOpenProj);

            Button btnOpenAddons = CreateButton("AddOns Klasörü", colBtn, colBtnHover, colText);
            btnOpenAddons.Width = 125;
            btnOpenAddons.Height = 32;
            btnOpenAddons.Click += delegate { OpenAddonsFolder(); };
            actionRow.Controls.Add(btnOpenAddons);

            // 2) Orta alan: Sol (Dosyalar) | Sag (TOC + Komutlar)
            TableLayoutPanel mid = new TableLayoutPanel();
            mid.Dock = DockStyle.Fill;
            mid.ColumnCount = 2;
            mid.RowCount = 1;
            mid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 58F));
            mid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 42F));
            mid.Margin = new Padding(0, 0, 0, 10);
            root.Controls.Add(mid, 0, 1);

            // Sol Kart: Addon Dosyalari
            Panel cardFiles = CreateCard("2. Addon Dosyaları (QuestGoToZ.toc)");
            cardFiles.Dock = DockStyle.Fill;
            cardFiles.Margin = new Padding(0, 0, 8, 0);
            mid.Controls.Add(cardFiles, 0, 0);

            Panel cFilesBody = (Panel)cardFiles.Tag;

            lvFiles = new ListView();
            lvFiles.Dock = DockStyle.Fill;
            lvFiles.View = View.Details;
            lvFiles.FullRowSelect = true;
            lvFiles.GridLines = false;
            lvFiles.BorderStyle = BorderStyle.FixedSingle;
            lvFiles.BackColor = colInput;
            lvFiles.ForeColor = colText;
            lvFiles.HeaderStyle = ColumnHeaderStyle.Nonclickable;
            lvFiles.Columns.Add("Dosya", 175);
            lvFiles.Columns.Add("Boyut", 78, HorizontalAlignment.Right);
            lvFiles.Columns.Add("Son Değişiklik", 130, HorizontalAlignment.Center);
            lvFiles.Columns.Add("Durum", 80, HorizontalAlignment.Center);
            lvFiles.DoubleClick += delegate { OpenSelectedFile(); };
            cFilesBody.Controls.Add(lvFiles);

            Panel fileBtnRow = new Panel();
            fileBtnRow.Dock = DockStyle.Bottom;
            fileBtnRow.Height = 40;
            fileBtnRow.Padding = new Padding(0, 8, 0, 0);
            cFilesBody.Controls.Add(fileBtnRow);

            Button btnOpenFile = CreateButton("Seçili Dosyayı Aç", colBtn, colBtnHover, colText);
            btnOpenFile.Width = 140;
            btnOpenFile.Height = 30;
            btnOpenFile.Dock = DockStyle.Left;
            btnOpenFile.Click += delegate { OpenSelectedFile(); };
            fileBtnRow.Controls.Add(btnOpenFile);

            Button btnZip = CreateButton("ZIP Paketi Oluştur", colBtn, colBtnHover, colText);
            btnZip.Width = 150;
            btnZip.Height = 30;
            btnZip.Dock = DockStyle.Right;
            btnZip.Click += delegate { ActionCreateZip(); };
            fileBtnRow.Controls.Add(btnZip);

            // Sag Sutun
            TableLayoutPanel rightCol = new TableLayoutPanel();
            rightCol.Dock = DockStyle.Fill;
            rightCol.ColumnCount = 1;
            rightCol.RowCount = 2;
            rightCol.RowStyles.Add(new RowStyle(SizeType.Absolute, 146F));
            rightCol.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            rightCol.Margin = new Padding(4, 0, 0, 0);
            mid.Controls.Add(rightCol, 1, 0);

            // Sag Ust: TOC
            Panel cardToc = CreateCard("3. TOC Sürüm Bilgisi");
            cardToc.Dock = DockStyle.Fill;
            cardToc.Margin = new Padding(0, 0, 0, 10);
            rightCol.Controls.Add(cardToc, 0, 0);

            Panel cTocBody = (Panel)cardToc.Tag;

            TableLayoutPanel tocGrid = new TableLayoutPanel();
            tocGrid.Dock = DockStyle.Top;
            tocGrid.Height = 62;
            tocGrid.ColumnCount = 2;
            tocGrid.RowCount = 2;
            tocGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 78F));
            tocGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            tocGrid.RowStyles.Add(new RowStyle(SizeType.Absolute, 30F));
            tocGrid.RowStyles.Add(new RowStyle(SizeType.Absolute, 30F));
            cTocBody.Controls.Add(tocGrid);

            Label lblIface = new Label();
            lblIface.Text = "Interface:";
            lblIface.ForeColor = colMuted;
            lblIface.TextAlign = ContentAlignment.MiddleLeft;
            lblIface.Dock = DockStyle.Fill;
            tocGrid.Controls.Add(lblIface, 0, 0);

            txtInterface = CreateTextBox();
            txtInterface.Dock = DockStyle.Fill;
            txtInterface.Margin = new Padding(0, 2, 0, 2);
            tocGrid.Controls.Add(txtInterface, 1, 0);

            Label lblVer = new Label();
            lblVer.Text = "Version:";
            lblVer.ForeColor = colMuted;
            lblVer.TextAlign = ContentAlignment.MiddleLeft;
            lblVer.Dock = DockStyle.Fill;
            tocGrid.Controls.Add(lblVer, 0, 1);

            txtVersion = CreateTextBox();
            txtVersion.Dock = DockStyle.Fill;
            txtVersion.Margin = new Padding(0, 2, 0, 2);
            tocGrid.Controls.Add(txtVersion, 1, 1);

            Button btnSaveToc = CreateButton("TOC Dosyasını Güncelle", colBtn, colBtnHover, colText);
            btnSaveToc.Width = 175;
            btnSaveToc.Height = 29;
            btnSaveToc.Dock = DockStyle.Bottom;
            btnSaveToc.Click += delegate { ActionSaveToc(); };
            cTocBody.Controls.Add(btnSaveToc);

            // Sag Alt: Oyun Ici Komutlar
            Panel cardCmd = CreateCard("4. Oyun İçi Komutlar (Tıkla & Kopyala)");
            cardCmd.Dock = DockStyle.Fill;
            rightCol.Controls.Add(cardCmd, 0, 1);

            Panel cCmdBody = (Panel)cardCmd.Tag;
            TableLayoutPanel cmdList = new TableLayoutPanel();
            cmdList.Dock = DockStyle.Fill;
            cmdList.ColumnCount = 2;
            cmdList.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 58F));
            cmdList.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 42F));
            cCmdBody.Controls.Add(cmdList);

            string[,] cmds = new string[,]
            {
                { "/reload", "Arayüzü yenile" },
                { "/qgt", "Ayar penceresi" },
                { "/qgt nearest", "En yakın görev" },
                { "/console scriptErrors 1", "Lua hatalarını aç" },
                { "/run print((select(4, GetBuildInfo())))", "Interface no gör" }
            };

            cmdList.RowCount = cmds.GetLength(0);
            for (int i = 0; i < cmds.GetLength(0); i++)
            {
                cmdList.RowStyles.Add(new RowStyle(SizeType.Percent, 20F));
                string cmdText = cmds[i, 0];
                string desc = cmds[i, 1];
                string btnLabel = cmdText.Length <= 24 ? cmdText : cmdText.Substring(0, 22) + "...";

                Button b = CreateButton(btnLabel, colBtn, colBtnHover, colText);
                b.Dock = DockStyle.Fill;
                b.Font = new Font("Consolas", 8.5F, FontStyle.Bold);
                b.Margin = new Padding(0, 2, 6, 2);
                b.Click += delegate { CopyCommand(cmdText); };
                cmdList.Controls.Add(b, 0, i);

                Label l = new Label();
                l.Text = desc;
                l.ForeColor = colMuted;
                l.Font = new Font("Segoe UI", 8.5F);
                l.TextAlign = ContentAlignment.MiddleRight;
                l.Dock = DockStyle.Fill;
                cmdList.Controls.Add(l, 1, i);
            }

            // 3) Alt Kart: Islem Gunlugu
            Panel cardLog = CreateCard("İşlem Günlüğü");
            cardLog.Dock = DockStyle.Fill;
            root.Controls.Add(cardLog, 0, 2);

            Panel cLogBody = (Panel)cardLog.Tag;
            rtbLog = new RichTextBox();
            rtbLog.Dock = DockStyle.Fill;
            rtbLog.ReadOnly = true;
            rtbLog.BorderStyle = BorderStyle.None;
            rtbLog.BackColor = colInput;
            rtbLog.ForeColor = colText;
            rtbLog.Font = new Font("Consolas", 9F);
            cLogBody.Controls.Add(rtbLog);

            this.Resize += delegate { PositionBadge(topPanel); };
            PositionBadge(topPanel);
        }

        private void PositionBadge(Panel topPanel)
        {
            if (lblStatusBadge != null && topPanel != null)
            {
                lblStatusBadge.Location = new Point(
                    Math.Max(360, topPanel.ClientSize.Width - lblStatusBadge.Width - 18),
                    18
                );
            }
        }

        private Panel CreateCard(string title)
        {
            Panel outer = new Panel();
            outer.BackColor = colCard;
            outer.Padding = new Padding(14, 10, 14, 12);
            outer.Paint += delegate(object s, PaintEventArgs e)
            {
                using (Pen p = new Pen(colBorder, 1))
                {
                    e.Graphics.DrawRectangle(p, 0, 0, outer.Width - 1, outer.Height - 1);
                }
            };

            Label lbl = new Label();
            lbl.Text = title;
            lbl.Font = new Font("Segoe UI", 9.5F, FontStyle.Bold);
            lbl.ForeColor = colGold;
            lbl.Dock = DockStyle.Top;
            lbl.Height = 24;
            outer.Controls.Add(lbl);

            Panel body = new Panel();
            body.Dock = DockStyle.Fill;
            body.BackColor = colCard;
            outer.Controls.Add(body);
            body.BringToFront();

            outer.Tag = body;
            return outer;
        }

        private TextBox CreateTextBox()
        {
            TextBox tb = new TextBox();
            tb.BackColor = colInput;
            tb.ForeColor = colText;
            tb.BorderStyle = BorderStyle.FixedSingle;
            tb.Font = new Font("Consolas", 9.5F);
            return tb;
        }

        private Button CreateButton(string text, Color bg, Color hover, Color fg)
        {
            Button btn = new Button();
            btn.Text = text;
            btn.BackColor = bg;
            btn.ForeColor = fg;
            btn.FlatStyle = FlatStyle.Flat;
            btn.FlatAppearance.BorderSize = 0;
            btn.FlatAppearance.MouseOverBackColor = hover;
            btn.FlatAppearance.MouseDownBackColor = hover;
            btn.Cursor = Cursors.Hand;
            btn.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
            return btn;
        }

        // ------------------------------------------------------------------
        // Config
        // ------------------------------------------------------------------
        private void LoadConfig()
        {
            if (!File.Exists(configPath)) return;
            try
            {
                foreach (string line in File.ReadAllLines(configPath, Encoding.UTF8))
                {
                    int idx = line.IndexOf('=');
                    if (idx > 0)
                    {
                        string key = line.Substring(0, idx).Trim();
                        string val = line.Substring(idx + 1).Trim();
                        if (key == "wow_path")
                        {
                            txtWowPath.Text = val;
                        }
                    }
                }
            }
            catch { }
        }

        private void SaveConfig()
        {
            try
            {
                Directory.CreateDirectory(toolsDir);
                File.WriteAllText(configPath, "wow_path=" + txtWowPath.Text.Trim() + Environment.NewLine, Encoding.UTF8);
            }
            catch (Exception ex)
            {
                Log("Ayar kaydedilemedi: " + ex.Message, colRed);
            }
        }

        // ------------------------------------------------------------------
        // Yol ve TOC Yardimcilari
        // ------------------------------------------------------------------
        private string ResolveAddonsDir(string selected)
        {
            if (string.IsNullOrWhiteSpace(selected)) return null;
            string p = selected.Trim().Trim('"');
            if (!Directory.Exists(p)) return null;

            string name = Path.GetFileName(p.TrimEnd('\\'));
            DirectoryInfo parent = Directory.GetParent(p.TrimEnd('\\'));

            if (string.Equals(name, AddonName, StringComparison.OrdinalIgnoreCase) &&
                parent != null &&
                string.Equals(parent.Name, "AddOns", StringComparison.OrdinalIgnoreCase))
            {
                return parent.FullName;
            }
            if (string.Equals(name, "AddOns", StringComparison.OrdinalIgnoreCase))
            {
                return p;
            }
            if (string.Equals(name, "Interface", StringComparison.OrdinalIgnoreCase))
            {
                return Path.Combine(p, "AddOns");
            }
            if (Directory.Exists(Path.Combine(p, "_forever_")))
            {
                return Path.Combine(p, "_forever_", "Interface", "AddOns");
            }
            if (Directory.Exists(Path.Combine(p, "_retail_")))
            {
                return Path.Combine(p, "_retail_", "Interface", "AddOns");
            }
            if (Directory.Exists(Path.Combine(p, "_classic_")))
            {
                return Path.Combine(p, "_classic_", "Interface", "AddOns");
            }
            return Path.Combine(p, "Interface", "AddOns");
        }

        private string GetTargetAddonDir()
        {
            string addonsDir = ResolveAddonsDir(txtWowPath.Text);
            if (string.IsNullOrEmpty(addonsDir)) return null;
            return Path.Combine(addonsDir, AddonName);
        }

        private bool IsReparsePoint(string path)
        {
            if (!Directory.Exists(path)) return false;
            try
            {
                FileAttributes attr = File.GetAttributes(path);
                return (attr & FileAttributes.ReparsePoint) == FileAttributes.ReparsePoint;
            }
            catch
            {
                return false;
            }
        }

        private List<string> ParseToc(out string iface, out string version)
        {
            iface = "";
            version = "";
            List<string> files = new List<string>();
            if (!File.Exists(tocPath)) return files;

            foreach (string rawLine in File.ReadAllLines(tocPath, Encoding.UTF8))
            {
                string line = rawLine.Trim();
                if (string.IsNullOrEmpty(line)) continue;
                if (line.StartsWith("##"))
                {
                    Match m = Regex.Match(line, @"^##\s*([^:]+)\s*:\s*(.*)$");
                    if (m.Success)
                    {
                        string k = m.Groups[1].Value.Trim();
                        string v = m.Groups[2].Value.Trim();
                        if (string.Equals(k, "Interface", StringComparison.OrdinalIgnoreCase)) iface = v;
                        if (string.Equals(k, "Version", StringComparison.OrdinalIgnoreCase)) version = v;
                    }
                }
                else if (!line.StartsWith("#"))
                {
                    files.Add(line);
                }
            }
            return files;
        }

        private List<string> GetAddonFiles()
        {
            string iface, ver;
            List<string> relFiles = ParseToc(out iface, out ver);
            List<string> result = new List<string>();
            result.Add(tocPath);
            foreach (string rel in relFiles)
            {
                result.Add(Path.Combine(projectDir, rel));
            }
            return result;
        }

        private string ComputeSha256(string filePath)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream fs = File.OpenRead(filePath))
            {
                byte[] hash = sha.ComputeHash(fs);
                return BitConverter.ToString(hash);
            }
        }

        // ------------------------------------------------------------------
        // Yenileme
        // ------------------------------------------------------------------
        private void RefreshAll()
        {
            RefreshTocAndFiles();
            RefreshStatus();
        }

        private void RefreshTocAndFiles()
        {
            string iface, ver;
            ParseToc(out iface, out ver);
            txtInterface.Text = iface;
            txtVersion.Text = ver;

            lvFiles.BeginUpdate();
            lvFiles.Items.Clear();
            foreach (string fullPath in GetAddonFiles())
            {
                string rel = fullPath.StartsWith(projectDir, StringComparison.OrdinalIgnoreCase)
                    ? fullPath.Substring(projectDir.Length).TrimStart('\\')
                    : Path.GetFileName(fullPath);

                ListViewItem item = new ListViewItem(rel);
                if (File.Exists(fullPath))
                {
                    FileInfo fi = new FileInfo(fullPath);
                    item.SubItems.Add(string.Format("{0:0.0} KB", fi.Length / 1024.0));
                    item.SubItems.Add(fi.LastWriteTime.ToString("yyyy-MM-dd HH:mm"));
                    item.SubItems.Add("Hazır");
                    item.ForeColor = colText;
                }
                else
                {
                    item.SubItems.Add("-");
                    item.SubItems.Add("-");
                    item.SubItems.Add("EKSİK!");
                    item.ForeColor = colRed;
                }
                lvFiles.Items.Add(item);
            }
            lvFiles.EndUpdate();
        }

        private void RefreshStatus()
        {
            string target = GetTargetAddonDir();
            if (string.IsNullOrEmpty(target))
            {
                lblTargetPreview.Text = "Hedef: Geçerli bir WoW klasörü seçin";
                SetBadge("WoW Klasörü Seçilmedi", colRed, colRedBg);
                return;
            }

            lblTargetPreview.Text = "Hedef Addon Klasörü: " + target;

            if (IsReparsePoint(target))
            {
                SetBadge("● Junction (Canlı Bağlı)", colGreen, colGreenBg);
            }
            else if (Directory.Exists(target))
            {
                bool inSync = true;
                foreach (string src in GetAddonFiles())
                {
                    if (!File.Exists(src)) continue;
                    string rel = src.Substring(projectDir.Length).TrimStart('\\');
                    string dst = Path.Combine(target, rel);
                    if (!File.Exists(dst) || ComputeSha256(src) != ComputeSha256(dst))
                    {
                        inSync = false;
                        break;
                    }
                }
                if (inSync)
                    SetBadge("● Kopya Kurulu (Güncel)", colBlueHover, Color.FromArgb(19, 34, 59));
                else
                    SetBadge("● Kopya Kurulu (Güncelleme Gerekli)", colYellow, colYellowBg);
            }
            else
            {
                SetBadge("○ Kurulu Değil", colRed, colRedBg);
            }
        }

        private void SetBadge(string text, Color fg, Color bg)
        {
            lblStatusBadge.Text = text;
            lblStatusBadge.ForeColor = fg;
            lblStatusBadge.BackColor = bg;
            PositionBadge(lblStatusBadge.Parent as Panel);
        }

        // ------------------------------------------------------------------
        // Aksiyonlar
        // ------------------------------------------------------------------
        private void BrowseWowFolder()
        {
            using (FolderBrowserDialog dlg = new FolderBrowserDialog())
            {
                dlg.Description = "WoW: Forever veya Interface\\AddOns klasörünü seçin";
                if (!string.IsNullOrWhiteSpace(txtWowPath.Text) && Directory.Exists(txtWowPath.Text))
                    dlg.SelectedPath = txtWowPath.Text;

                if (dlg.ShowDialog(this) == DialogResult.OK)
                {
                    txtWowPath.Text = dlg.SelectedPath;
                    SaveConfig();
                    RefreshStatus();
                    Log("WoW klasörü seçildi: " + dlg.SelectedPath, colText);
                }
            }
        }

        private void AutoDetectWow()
        {
            string[] commonRel = new string[]
            {
                "World of Warcraft",
                @"Program Files (x86)\World of Warcraft",
                @"Program Files\World of Warcraft",
                @"Games\World of Warcraft",
                @"Games\WoW",
                @"Games\WoW Forever",
                "WoW Forever",
                "WoW"
            };

            foreach (DriveInfo drv in DriveInfo.GetDrives())
            {
                if (!drv.IsReady) continue;
                foreach (string rel in commonRel)
                {
                    string candidate = Path.Combine(drv.RootDirectory.FullName, rel);
                    if (Directory.Exists(candidate))
                    {
                        txtWowPath.Text = candidate;
                        SaveConfig();
                        RefreshStatus();
                        Log("Otomatik bulundu: " + candidate, colGreen);
                        return;
                    }
                }
            }

            Log("Yaygın konumlarda WoW klasörü bulunamadı. Lütfen 'Gözat...' ile seçin.", colYellow);
            MessageBox.Show(this, "Yaygın konumlarda WoW klasörü bulunamadı.\nLütfen 'Gözat...' butonuyla manuel seçin.",
                "Otomatik Arama", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private void ActionCreateJunction()
        {
            string target = GetTargetAddonDir();
            if (string.IsNullOrEmpty(target))
            {
                MessageBox.Show(this, "Önce geçerli bir WoW klasörü seçin.", "Uyarı", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            string parentDir = Path.GetDirectoryName(target);
            if (!string.IsNullOrEmpty(parentDir))
                Directory.CreateDirectory(parentDir);

            if (Directory.Exists(target))
            {
                if (IsReparsePoint(target))
                {
                    RunCmd("rmdir \"" + target + "\"");
                }
                else
                {
                    DialogResult dr = MessageBox.Show(
                        this,
                        "Hedefte zaten bir klasör var:\n" + target + "\n\nBu kopyayı silip yerine canlı Junction bağlantısı oluşturmak istiyor musunuz?",
                        "Mevcut Klasör Bulundu",
                        MessageBoxButtons.YesNo,
                        MessageBoxIcon.Question);
                    if (dr != DialogResult.Yes) return;
                    Directory.Delete(target, true);
                }
            }

            string output;
            int code = RunCmd("mklink /J \"" + target + "\" \"" + projectDir + "\"", out output);
            if (code == 0)
            {
                Log("Junction oluşturuldu: " + target + " -> " + projectDir, colGreen);
                Log("Artık kod değişikliklerinden sonra oyunda /reload yapmanız yeterli.", colMuted);
            }
            else
            {
                Log("Junction hatası: " + output, colRed);
                MessageBox.Show(this, "Junction oluşturulamadı:\n" + output, "Hata", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            RefreshStatus();
        }

        private void ActionCopyFiles()
        {
            string target = GetTargetAddonDir();
            if (string.IsNullOrEmpty(target))
            {
                MessageBox.Show(this, "Önce geçerli bir WoW klasörü seçin.", "Uyarı", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            if (IsReparsePoint(target))
            {
                DialogResult dr = MessageBox.Show(
                    this,
                    "Hedef zaten canlı Junction ile bağlı (dosyalar anında güncel).\nJunction'ı kaldırıp dosya kopyalama moduna geçmek istiyor musunuz?",
                    "Junction Aktif",
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Question);
                if (dr != DialogResult.Yes) return;
                RunCmd("rmdir \"" + target + "\"");
            }

            Directory.CreateDirectory(target);
            int copied = 0;
            foreach (string src in GetAddonFiles())
            {
                if (!File.Exists(src))
                {
                    Log("Eksik dosya atlandı: " + Path.GetFileName(src), colYellow);
                    continue;
                }
                string rel = src.Substring(projectDir.Length).TrimStart('\\');
                string dst = Path.Combine(target, rel);
                string dstDir = Path.GetDirectoryName(dst);
                if (!string.IsNullOrEmpty(dstDir)) Directory.CreateDirectory(dstDir);
                File.Copy(src, dst, true);
                copied++;
            }

            Log(string.Format("{0} addon dosyası kopyalandı -> {1}", copied, target), colGreen);
            RefreshStatus();
        }

        private void ActionUninstall()
        {
            string target = GetTargetAddonDir();
            if (string.IsNullOrEmpty(target) || !Directory.Exists(target))
            {
                Log("Kaldırılacak bir kurulum bulunamadı.", colYellow);
                return;
            }

            DialogResult dr = MessageBox.Show(
                this,
                "Şu hedefteki bağlantı/kopya kaldırılacak:\n" + target + "\n\n(Proje klasörünüzdeki kaynak dosyalara dokunulmaz.)\nDevam edilsin mi?",
                "Kurulumu Kaldır",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning);
            if (dr != DialogResult.Yes) return;

            try
            {
                if (IsReparsePoint(target))
                {
                    string output;
                    int code = RunCmd("rmdir \"" + target + "\"", out output);
                    if (code != 0) throw new Exception(output);
                    Log("Junction bağlantısı kaldırıldı: " + target, colGreen);
                }
                else
                {
                    Directory.Delete(target, true);
                    Log("Kopya klasör silindi: " + target, colGreen);
                }
            }
            catch (Exception ex)
            {
                Log("Kaldırma hatası: " + ex.Message, colRed);
                MessageBox.Show(this, ex.Message, "Hata", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            RefreshStatus();
        }

        private void ActionSaveToc()
        {
            if (!File.Exists(tocPath))
            {
                MessageBox.Show(this, "QuestGoToZ.toc bulunamadı.", "Hata", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            string newIface = txtInterface.Text.Trim();
            string newVer = txtVersion.Text.Trim();
            if (string.IsNullOrEmpty(newIface))
            {
                MessageBox.Show(this, "Interface alanı boş olamaz (ör. 16001).", "Uyarı", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            string content = File.ReadAllText(tocPath, Encoding.UTF8);
            if (Regex.IsMatch(content, @"^##\s*Interface\s*:.*$", RegexOptions.Multiline))
                content = Regex.Replace(content, @"^##\s*Interface\s*:.*$", "## Interface: " + newIface, RegexOptions.Multiline);
            else
                content = "## Interface: " + newIface + Environment.NewLine + content;

            if (!string.IsNullOrEmpty(newVer))
            {
                if (Regex.IsMatch(content, @"^##\s*Version\s*:.*$", RegexOptions.Multiline))
                    content = Regex.Replace(content, @"^##\s*Version\s*:.*$", "## Version: " + newVer, RegexOptions.Multiline);
                else
                    content = "## Version: " + newVer + Environment.NewLine + content;
            }

            File.WriteAllText(tocPath, content, Encoding.UTF8);
            Log(string.Format("QuestGoToZ.toc güncellendi (Interface: {0}, Version: {1})", newIface, newVer), colGreen);
            RefreshAll();
        }

        private void ActionCreateZip()
        {
            try
            {
                Directory.CreateDirectory(buildsDir);
                string ver = string.IsNullOrWhiteSpace(txtVersion.Text) ? "1.0.0" : txtVersion.Text.Trim();
                string zipName = string.Format("{0}-v{1}-{2}.zip", AddonName, ver, DateTime.Now.ToString("yyyyMMdd_HHmm"));
                string zipPath = Path.Combine(buildsDir, zipName);
                if (File.Exists(zipPath)) File.Delete(zipPath);

                using (ZipArchive za = ZipFile.Open(zipPath, ZipArchiveMode.Create))
                {
                    foreach (string src in GetAddonFiles())
                    {
                        if (!File.Exists(src)) continue;
                        string rel = src.Substring(projectDir.Length).TrimStart('\\').Replace('\\', '/');
                        za.CreateEntryFromFile(src, AddonName + "/" + rel, CompressionLevel.Optimal);
                    }
                }

                Log("ZIP paketi oluşturuldu: " + zipPath, colGreen);
                OpenInExplorer(buildsDir);
            }
            catch (Exception ex)
            {
                Log("ZIP oluşturma hatası: " + ex.Message, colRed);
                MessageBox.Show(this, ex.Message, "Hata", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void OpenSelectedFile()
        {
            if (lvFiles.SelectedItems.Count == 0)
            {
                Log("Önce listeden bir dosya seçin.", colYellow);
                return;
            }
            string rel = lvFiles.SelectedItems[0].Text;
            string fullPath = Path.Combine(projectDir, rel);
            if (File.Exists(fullPath))
            {
                Process.Start(new ProcessStartInfo(fullPath) { UseShellExecute = true });
                Log("Dosya açıldı: " + rel, colText);
            }
        }

        private void OpenAddonsFolder()
        {
            string addonsDir = ResolveAddonsDir(txtWowPath.Text);
            if (!string.IsNullOrEmpty(addonsDir) && Directory.Exists(addonsDir))
                OpenInExplorer(addonsDir);
            else
                MessageBox.Show(this, "Geçerli bir AddOns klasörü bulunamadı.", "Uyarı", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        private void OpenInExplorer(string path)
        {
            if (Directory.Exists(path))
                Process.Start(new ProcessStartInfo("explorer.exe", "\"" + path + "\"") { UseShellExecute = true });
        }

        private void CopyCommand(string cmd)
        {
            try
            {
                Clipboard.SetText(cmd);
                Log("Panoya kopyalandı: " + cmd, colGreen);
            }
            catch (Exception ex)
            {
                Log("Kopyalama hatası: " + ex.Message, colRed);
            }
        }

        private int RunCmd(string command)
        {
            string dummy;
            return RunCmd(command, out dummy);
        }

        private int RunCmd(string command, out string output)
        {
            ProcessStartInfo psi = new ProcessStartInfo("cmd.exe", "/c " + command);
            psi.CreateNoWindow = true;
            psi.UseShellExecute = false;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            using (Process p = Process.Start(psi))
            {
                string stdout = p.StandardOutput.ReadToEnd();
                string stderr = p.StandardError.ReadToEnd();
                p.WaitForExit();
                output = (stderr + " " + stdout).Trim();
                return p.ExitCode;
            }
        }

        private void Log(string message, Color color)
        {
            string line = string.Format("[{0}] {1}{2}", DateTime.Now.ToString("HH:mm:ss"), message, Environment.NewLine);
            rtbLog.SelectionStart = rtbLog.TextLength;
            rtbLog.SelectionLength = 0;
            rtbLog.SelectionColor = color;
            rtbLog.AppendText(line);
            rtbLog.ScrollToCaret();
        }
    }
}
