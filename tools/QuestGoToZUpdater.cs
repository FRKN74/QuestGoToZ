using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

namespace QuestGoToZUpdaterApp
{
    static class Program
    {
        [DllImport("user32.dll")]
        private static extern bool SetProcessDPIAware();

        [STAThread]
        static void Main()
        {
            try { SetProcessDPIAware(); } catch { }
            try { ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072 | SecurityProtocolType.Tls12; } catch { }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new UpdaterForm());
        }
    }

    public class UpdaterForm : Form
    {
        private const string AddonName = "QuestGoToZ";
        private const string GitHubOwner = "FRKN74";
        private const string GitHubRepo = "QuestGoToZ";
        private const string LatestReleaseApi = "https://api.github.com/repos/" + GitHubOwner + "/" + GitHubRepo + "/releases/latest";
        private const string FallbackMainZip = "https://github.com/" + GitHubOwner + "/" + GitHubRepo + "/archive/refs/heads/main.zip";
        private const string RepoWebUrl = "https://github.com/" + GitHubOwner + "/" + GitHubRepo;

        private readonly string configDir;
        private readonly string configPath;

        private string latestTag = "";
        private string latestZipUrl = "";
        private bool isBusy = false;

        // Koyu WoW / Midnight temasi
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

        private Label lblStatusBadge;
        private TextBox txtWowPath;
        private Label lblTargetPreview;
        private Label lblInstalledVer;
        private Label lblRemoteVer;
        private Button btnInstall;
        private Button btnCheck;
        private Button btnUninstall;
        private RichTextBox rtbLog;

        public UpdaterForm()
        {
            configDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), AddonName);
            configPath = Path.Combine(configDir, "updater.cfg");

            BuildUI();
            LoadConfig();
            if (string.IsNullOrWhiteSpace(txtWowPath.Text))
            {
                AutoDetectWow(true);
            }
            RefreshLocalStatus();
            CheckRemoteVersionAsync();
        }

        private void BuildUI()
        {
            this.Text = AddonName + " — Kurucu ve Güncelleyici";
            this.Size = new Size(760, 580);
            this.MinimumSize = new Size(720, 540);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = colBg;
            this.ForeColor = colText;
            this.Font = new Font("Segoe UI", 9F);

            // Ust baslik
            Panel topPanel = new Panel();
            topPanel.Dock = DockStyle.Top;
            topPanel.Height = 66;
            topPanel.BackColor = colBg;
            this.Controls.Add(topPanel);

            Label lblTitle = new Label();
            lblTitle.Text = AddonName + " Kurucu & Güncelleyici";
            lblTitle.Font = new Font("Segoe UI", 14.5F, FontStyle.Bold);
            lblTitle.ForeColor = colGold;
            lblTitle.AutoSize = true;
            lblTitle.Location = new Point(18, 10);
            topPanel.Controls.Add(lblTitle);

            Label lblSub = new Label();
            lblSub.Text = "GitHub: " + GitHubOwner + "/" + GitHubRepo + " (WoW: Forever / Interface 16001)";
            lblSub.Font = new Font("Segoe UI", 8.5F);
            lblSub.ForeColor = colMuted;
            lblSub.AutoSize = true;
            lblSub.Location = new Point(20, 38);
            topPanel.Controls.Add(lblSub);

            lblStatusBadge = new Label();
            lblStatusBadge.Text = "Kontrol ediliyor...";
            lblStatusBadge.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
            lblStatusBadge.AutoSize = true;
            lblStatusBadge.Padding = new Padding(12, 6, 12, 6);
            lblStatusBadge.BackColor = colCard;
            lblStatusBadge.ForeColor = colText;
            lblStatusBadge.Location = new Point(540, 18);
            topPanel.Controls.Add(lblStatusBadge);

            // Ana icerik
            TableLayoutPanel root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.Padding = new Padding(18, 4, 18, 14);
            root.ColumnCount = 1;
            root.RowCount = 3;
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 128F));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 134F));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            root.BackColor = colBg;
            this.Controls.Add(root);
            root.BringToFront();

            // 1) WoW Klasor Karti
            Panel card1 = CreateCard("1. World of Warcraft Klasörünü Seç");
            card1.Dock = DockStyle.Fill;
            card1.Margin = new Padding(0, 0, 0, 10);
            root.Controls.Add(card1, 0, 0);
            Panel b1 = (Panel)card1.Tag;

            TableLayoutPanel pathRow = new TableLayoutPanel();
            pathRow.Dock = DockStyle.Top;
            pathRow.Height = 32;
            pathRow.ColumnCount = 3;
            pathRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            pathRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 96F));
            pathRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 118F));
            b1.Controls.Add(pathRow);

            txtWowPath = new TextBox();
            txtWowPath.BackColor = colInput;
            txtWowPath.ForeColor = colText;
            txtWowPath.BorderStyle = BorderStyle.FixedSingle;
            txtWowPath.Font = new Font("Consolas", 9.5F);
            txtWowPath.Dock = DockStyle.Fill;
            txtWowPath.Margin = new Padding(0, 2, 8, 2);
            txtWowPath.Leave += delegate { SaveConfig(); RefreshLocalStatus(); };
            pathRow.Controls.Add(txtWowPath, 0, 0);

            Button btnBrowse = CreateButton("Gözat...", colBtn, colBtnHover, colText);
            btnBrowse.Dock = DockStyle.Fill;
            btnBrowse.Margin = new Padding(0, 0, 6, 0);
            btnBrowse.Click += delegate { BrowseWowFolder(); };
            pathRow.Controls.Add(btnBrowse, 1, 0);

            Button btnAuto = CreateButton("Otomatik Ara", colBtn, colBtnHover, colText);
            btnAuto.Dock = DockStyle.Fill;
            btnAuto.Click += delegate { AutoDetectWow(false); };
            pathRow.Controls.Add(btnAuto, 2, 0);

            lblTargetPreview = new Label();
            lblTargetPreview.Text = "Hedef: Geçerli bir WoW klasörü seçin";
            lblTargetPreview.Font = new Font("Consolas", 8.5F);
            lblTargetPreview.ForeColor = colMuted;
            lblTargetPreview.Dock = DockStyle.Bottom;
            lblTargetPreview.Height = 24;
            b1.Controls.Add(lblTargetPreview);

            // 2) Surum ve Kurulum Karti
            Panel card2 = CreateCard("2. Kurulum ve GitHub Güncelleme");
            card2.Dock = DockStyle.Fill;
            card2.Margin = new Padding(0, 0, 0, 10);
            root.Controls.Add(card2, 0, 1);
            Panel b2 = (Panel)card2.Tag;

            Panel verRow = new Panel();
            verRow.Dock = DockStyle.Top;
            verRow.Height = 28;
            b2.Controls.Add(verRow);

            lblInstalledVer = new Label();
            lblInstalledVer.Text = "Kurulu Sürüm: -";
            lblInstalledVer.ForeColor = colText;
            lblInstalledVer.Font = new Font("Segoe UI", 9.5F, FontStyle.Bold);
            lblInstalledVer.AutoSize = true;
            lblInstalledVer.Location = new Point(0, 4);
            verRow.Controls.Add(lblInstalledVer);

            lblRemoteVer = new Label();
            lblRemoteVer.Text = "GitHub Son Sürüm: Kontrol ediliyor...";
            lblRemoteVer.ForeColor = colMuted;
            lblRemoteVer.Font = new Font("Segoe UI", 9.5F, FontStyle.Bold);
            lblRemoteVer.AutoSize = true;
            lblRemoteVer.Location = new Point(260, 4);
            verRow.Controls.Add(lblRemoteVer);

            FlowLayoutPanel btnRow = new FlowLayoutPanel();
            btnRow.Dock = DockStyle.Bottom;
            btnRow.Height = 40;
            btnRow.WrapContents = false;
            b2.Controls.Add(btnRow);

            btnInstall = CreateButton("İndir ve Kur / Güncelle", colGold, colGoldHover, Color.FromArgb(17, 20, 29));
            btnInstall.Width = 205;
            btnInstall.Height = 34;
            btnInstall.Margin = new Padding(0, 2, 8, 0);
            btnInstall.Click += delegate { InstallOrUpdateAsync(); };
            btnRow.Controls.Add(btnInstall);

            btnCheck = CreateButton("Güncellemeyi Kontrol Et", colBlue, colBlueHover, Color.White);
            btnCheck.Width = 175;
            btnCheck.Height = 34;
            btnCheck.Margin = new Padding(0, 2, 8, 0);
            btnCheck.Click += delegate { CheckRemoteVersionAsync(); };
            btnRow.Controls.Add(btnCheck);

            btnUninstall = CreateButton("Kaldır", Color.FromArgb(127, 29, 29), Color.FromArgb(153, 27, 27), Color.White);
            btnUninstall.Width = 86;
            btnUninstall.Height = 34;
            btnUninstall.Margin = new Padding(0, 2, 8, 0);
            btnUninstall.Click += delegate { UninstallAddon(); };
            btnRow.Controls.Add(btnUninstall);

            Button btnOpenAddons = CreateButton("AddOns Aç", colBtn, colBtnHover, colText);
            btnOpenAddons.Width = 98;
            btnOpenAddons.Height = 34;
            btnOpenAddons.Margin = new Padding(0, 2, 6, 0);
            btnOpenAddons.Click += delegate { OpenAddonsFolder(); };
            btnRow.Controls.Add(btnOpenAddons);

            Button btnGitHub = CreateButton("GitHub", colBtn, colBtnHover, colText);
            btnGitHub.Width = 76;
            btnGitHub.Height = 34;
            btnGitHub.Margin = new Padding(0, 2, 0, 0);
            btnGitHub.Click += delegate { Process.Start(new ProcessStartInfo(RepoWebUrl) { UseShellExecute = true }); };
            btnRow.Controls.Add(btnGitHub);

            // 3) Islem Gunlugu
            Panel card3 = CreateCard("İşlem Günlüğü");
            card3.Dock = DockStyle.Fill;
            root.Controls.Add(card3, 0, 2);
            Panel b3 = (Panel)card3.Tag;

            rtbLog = new RichTextBox();
            rtbLog.Dock = DockStyle.Fill;
            rtbLog.ReadOnly = true;
            rtbLog.BorderStyle = BorderStyle.None;
            rtbLog.BackColor = colInput;
            rtbLog.ForeColor = colText;
            rtbLog.Font = new Font("Consolas", 9F);
            b3.Controls.Add(rtbLog);

            this.Resize += delegate { PositionBadge(topPanel); };
            PositionBadge(topPanel);
        }

        private void PositionBadge(Panel topPanel)
        {
            if (lblStatusBadge != null && topPanel != null)
            {
                lblStatusBadge.Location = new Point(
                    Math.Max(340, topPanel.ClientSize.Width - lblStatusBadge.Width - 18),
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

        private void LoadConfig()
        {
            if (!File.Exists(configPath)) return;
            try
            {
                foreach (string line in File.ReadAllLines(configPath, Encoding.UTF8))
                {
                    int idx = line.IndexOf('=');
                    if (idx > 0 && line.Substring(0, idx).Trim() == "wow_path")
                    {
                        txtWowPath.Text = line.Substring(idx + 1).Trim();
                    }
                }
            }
            catch { }
        }

        private void SaveConfig()
        {
            try
            {
                Directory.CreateDirectory(configDir);
                File.WriteAllText(configPath, "wow_path=" + txtWowPath.Text.Trim() + Environment.NewLine, Encoding.UTF8);
            }
            catch { }
        }

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
                return parent.FullName;

            if (string.Equals(name, "AddOns", StringComparison.OrdinalIgnoreCase))
                return p;

            if (string.Equals(name, "Interface", StringComparison.OrdinalIgnoreCase))
                return Path.Combine(p, "AddOns");

            if (Directory.Exists(Path.Combine(p, "_forever_")))
                return Path.Combine(p, "_forever_", "Interface", "AddOns");

            if (Directory.Exists(Path.Combine(p, "_retail_")))
                return Path.Combine(p, "_retail_", "Interface", "AddOns");

            if (Directory.Exists(Path.Combine(p, "_classic_")))
                return Path.Combine(p, "_classic_", "Interface", "AddOns");

            return Path.Combine(p, "Interface", "AddOns");
        }

        private string GetTargetAddonDir()
        {
            string addonsDir = ResolveAddonsDir(txtWowPath.Text);
            return string.IsNullOrEmpty(addonsDir) ? null : Path.Combine(addonsDir, AddonName);
        }

        private string GetInstalledVersion()
        {
            string target = GetTargetAddonDir();
            if (string.IsNullOrEmpty(target)) return null;
            string toc = Path.Combine(target, AddonName + ".toc");
            if (!File.Exists(toc)) return null;

            try
            {
                foreach (string line in File.ReadAllLines(toc, Encoding.UTF8))
                {
                    Match m = Regex.Match(line.Trim(), @"^##\s*Version\s*:\s*(.+)$", RegexOptions.IgnoreCase);
                    if (m.Success) return m.Groups[1].Value.Trim();
                }
                return "1.0.0";
            }
            catch
            {
                return null;
            }
        }

        private string NormalizeVer(string v)
        {
            if (string.IsNullOrWhiteSpace(v)) return "";
            return v.Trim().TrimStart('v', 'V');
        }

        private void RefreshLocalStatus()
        {
            string target = GetTargetAddonDir();
            if (string.IsNullOrEmpty(target))
            {
                lblTargetPreview.Text = "Hedef: Geçerli bir WoW klasörü seçin";
                lblInstalledVer.Text = "Kurulu Sürüm: -";
                SetBadge("Klasör Seçilmedi", colRed, colRedBg);
                return;
            }

            lblTargetPreview.Text = "Hedef Klasör: " + target;
            string installed = GetInstalledVersion();
            if (string.IsNullOrEmpty(installed))
            {
                lblInstalledVer.Text = "Kurulu Sürüm: Kurulu Değil";
                SetBadge("○ Kurulu Değil", colRed, colRedBg);
                return;
            }

            lblInstalledVer.Text = "Kurulu Sürüm: v" + NormalizeVer(installed);
            if (!string.IsNullOrEmpty(latestTag))
            {
                if (string.Equals(NormalizeVer(installed), NormalizeVer(latestTag), StringComparison.OrdinalIgnoreCase))
                {
                    SetBadge("● Güncel (v" + NormalizeVer(installed) + ")", colGreen, colGreenBg);
                }
                else
                {
                    SetBadge("↑ Güncelleme Var (" + latestTag + ")", colYellow, colYellowBg);
                }
            }
            else
            {
                SetBadge("● Kurulu (v" + NormalizeVer(installed) + ")", colGreen, colGreenBg);
            }
        }

        private void SetBadge(string text, Color fg, Color bg)
        {
            lblStatusBadge.Text = text;
            lblStatusBadge.ForeColor = fg;
            lblStatusBadge.BackColor = bg;
            PositionBadge(lblStatusBadge.Parent as Panel);
        }

        private void SetBusy(bool busy)
        {
            isBusy = busy;
            btnInstall.Enabled = !busy;
            btnCheck.Enabled = !busy;
            btnUninstall.Enabled = !busy;
        }

        private void BrowseWowFolder()
        {
            using (FolderBrowserDialog dlg = new FolderBrowserDialog())
            {
                dlg.Description = "World of Warcraft (veya _forever_ / Interface\\AddOns) klasörünü seçin";
                if (!string.IsNullOrWhiteSpace(txtWowPath.Text) && Directory.Exists(txtWowPath.Text))
                    dlg.SelectedPath = txtWowPath.Text;

                if (dlg.ShowDialog(this) == DialogResult.OK)
                {
                    txtWowPath.Text = dlg.SelectedPath;
                    SaveConfig();
                    RefreshLocalStatus();
                    Log("WoW klasörü seçildi: " + dlg.SelectedPath, colText);
                }
            }
        }

        private void AutoDetectWow(bool silent)
        {
            string[] commonRel = new string[]
            {
                @"Program Files (x86)\World of Warcraft",
                @"Program Files\World of Warcraft",
                "World of Warcraft",
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
                        RefreshLocalStatus();
                        Log("WoW klasörü otomatik bulundu: " + candidate, colGreen);
                        return;
                    }
                }
            }

            if (!silent)
            {
                Log("Yaygın konumlarda WoW bulunamadı. Lütfen 'Gözat...' ile seçin.", colYellow);
                MessageBox.Show(this, "WoW klasörü otomatik bulunamadı.\nLütfen 'Gözat...' butonuyla manuel seçin.",
                    "Otomatik Arama", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        private void CheckRemoteVersionAsync()
        {
            if (isBusy) return;
            SetBusy(true);
            lblRemoteVer.Text = "GitHub Son Sürüm: Kontrol ediliyor...";
            Log("GitHub üzerinden son sürüm kontrol ediliyor...", colMuted);

            ThreadPool.QueueUserWorkItem(delegate
            {
                string tag = "";
                string zipUrl = "";
                string errMsg = null;

                try
                {
                    using (WebClient wc = new WebClient())
                    {
                        wc.Encoding = Encoding.UTF8;
                        wc.Headers.Add("User-Agent", "QuestGoToZ-Updater");
                        wc.Headers.Add("Accept", "application/vnd.github+json");
                        string json = wc.DownloadString(LatestReleaseApi);

                        Match mTag = Regex.Match(json, "\"tag_name\"\\s*:\\s*\"([^\"]+)\"");
                        if (mTag.Success) tag = mTag.Groups[1].Value;

                        Match mZip = Regex.Match(json, "\"browser_download_url\"\\s*:\\s*\"([^\"]+\\.zip)\"");
                        if (mZip.Success) zipUrl = mZip.Groups[1].Value;
                    }
                }
                catch (Exception ex)
                {
                    errMsg = ex.Message;
                }

                SafeUI(delegate
                {
                    SetBusy(false);
                    if (!string.IsNullOrEmpty(tag))
                    {
                        latestTag = tag;
                        latestZipUrl = string.IsNullOrEmpty(zipUrl) ? FallbackMainZip : zipUrl;
                        lblRemoteVer.Text = "GitHub Son Sürüm: " + latestTag;
                        lblRemoteVer.ForeColor = colGreen;
                        Log("GitHub son sürüm bulundu: " + latestTag, colGreen);
                    }
                    else
                    {
                        latestZipUrl = FallbackMainZip;
                        lblRemoteVer.Text = "GitHub Son Sürüm: main (doğrudan)";
                        lblRemoteVer.ForeColor = colYellow;
                        if (!string.IsNullOrEmpty(errMsg))
                            Log("Release bilgisi alınamadı, ana dal (main) kullanılacak: " + errMsg, colYellow);
                    }
                    RefreshLocalStatus();
                });
            });
        }

        private void InstallOrUpdateAsync()
        {
            if (isBusy) return;
            string targetDir = GetTargetAddonDir();
            if (string.IsNullOrEmpty(targetDir))
            {
                MessageBox.Show(this, "Önce geçerli bir World of Warcraft klasörü seçin.", "Uyarı",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            string downloadUrl = string.IsNullOrEmpty(latestZipUrl) ? FallbackMainZip : latestZipUrl;
            SetBusy(true);
            Log("İndiriliyor: " + downloadUrl, colText);

            ThreadPool.QueueUserWorkItem(delegate
            {
                string tempRoot = Path.Combine(Path.GetTempPath(), "QuestGoToZ_Update_" + Guid.NewGuid().ToString("N"));
                string tempZip = Path.Combine(tempRoot, "addon.zip");
                string extractDir = Path.Combine(tempRoot, "extracted");
                int copiedCount = 0;
                string errMsg = null;

                try
                {
                    Directory.CreateDirectory(tempRoot);
                    using (WebClient wc = new WebClient())
                    {
                        wc.Headers.Add("User-Agent", "QuestGoToZ-Updater");
                        wc.DownloadFile(downloadUrl, tempZip);
                    }

                    ZipFile.ExtractToDirectory(tempZip, extractDir);

                    // ZIP icinde QuestGoToZ.toc dosyasinin bulundugu klasoru bul
                    string[] tocs = Directory.GetFiles(extractDir, AddonName + ".toc", SearchOption.AllDirectories);
                    if (tocs.Length == 0)
                        throw new Exception("İndirilen paket içinde " + AddonName + ".toc bulunamadı.");

                    string sourceAddonDir = Path.GetDirectoryName(tocs[0]);
                    Directory.CreateDirectory(targetDir);

                    // Yalnizca temiz addon dosyalarini (.toc ve .lua) ustune yazarak kopyala
                    foreach (string file in Directory.GetFiles(sourceAddonDir))
                    {
                        string ext = Path.GetExtension(file).ToLowerInvariant();
                        if (ext == ".toc" || ext == ".lua")
                        {
                            string dest = Path.Combine(targetDir, Path.GetFileName(file));
                            File.Copy(file, dest, true);
                            copiedCount++;
                        }
                    }
                }
                catch (Exception ex)
                {
                    errMsg = ex.Message;
                }
                finally
                {
                    try { if (Directory.Exists(tempRoot)) Directory.Delete(tempRoot, true); } catch { }
                }

                SafeUI(delegate
                {
                    SetBusy(false);
                    if (string.IsNullOrEmpty(errMsg))
                    {
                        Log(string.Format("Başarıyla kuruldu/güncellendi! ({0} dosya -> {1})", copiedCount, targetDir), colGreen);
                        Log("Oyundaysanız /reload yazmanız yeterli (ilk kurulumsa oyunu kapatıp açın).", colGold);
                        RefreshLocalStatus();
                    }
                    else
                    {
                        Log("Kurulum hatası: " + errMsg, colRed);
                        MessageBox.Show(this, "Kurulum/güncelleme sırasında hata oluştu:\n" + errMsg,
                            "Hata", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    }
                });
            });
        }

        private void UninstallAddon()
        {
            string target = GetTargetAddonDir();
            if (string.IsNullOrEmpty(target) || !Directory.Exists(target))
            {
                Log("Kaldırılacak kurulum bulunamadı.", colYellow);
                return;
            }

            DialogResult dr = MessageBox.Show(
                this,
                "QuestGoToZ addonu şu klasörden kaldırılacak:\n" + target + "\n\n(Oyun içi ayarlarınız WTF klasöründe güvende kalır.)\nDevam edilsin mi?",
                "Addonu Kaldır",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning);

            if (dr != DialogResult.Yes) return;

            try
            {
                Directory.Delete(target, true);
                Log("Addon kaldırıldı: " + target, colGreen);
            }
            catch (Exception ex)
            {
                Log("Kaldırma hatası: " + ex.Message, colRed);
            }
            RefreshLocalStatus();
        }

        private void OpenAddonsFolder()
        {
            string addonsDir = ResolveAddonsDir(txtWowPath.Text);
            if (!string.IsNullOrEmpty(addonsDir) && Directory.Exists(addonsDir))
                Process.Start(new ProcessStartInfo("explorer.exe", "\"" + addonsDir + "\"") { UseShellExecute = true });
            else
                MessageBox.Show(this, "Geçerli bir AddOns klasörü bulunamadı.", "Uyarı", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        private void SafeUI(Action action)
        {
            if (this.IsDisposed) return;
            if (this.InvokeRequired)
                this.BeginInvoke(action);
            else
                action();
        }

        private void Log(string msg, Color color)
        {
            string line = string.Format("[{0}] {1}{2}", DateTime.Now.ToString("HH:mm:ss"), msg, Environment.NewLine);
            rtbLog.SelectionStart = rtbLog.TextLength;
            rtbLog.SelectionLength = 0;
            rtbLog.SelectionColor = color;
            rtbLog.AppendText(line);
            rtbLog.ScrollToCaret();
        }
    }
}
