using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace BarCustomTestLauncher
{
    internal sealed class ServerConfig
    {
        public string server_name { get; set; }
        public string lobby_host { get; set; }
        public int lobby_port { get; set; }
        public string room_name { get; set; }
        public string pve_status_source { get; set; }
        public string dev_source { get; set; }
        public string dev_engine_version { get; set; }
    }

    internal sealed class CommandResult
    {
        public int ExitCode;
        public string Output;
        public string Error;
    }

    internal sealed class MainForm : Form
    {
        private readonly string baseDirectory;
        private readonly string actionScript;
        private readonly string pveScript;
        private readonly ServerConfig server;
        private readonly TextBox configPath = new TextBox();
        private readonly TextBox devPath = new TextBox();
        private readonly ComboBox modeSelect = new ComboBox();
        private readonly ComboBox rollbackVersions = new ComboBox();
        private readonly Label devLabel = new Label();
        private readonly Label rollbackLabel = new Label();
        private readonly Label status = new Label();
        private readonly Button connectButton = new Button();
        private readonly Button restoreButton = new Button();
        private readonly Button selectButton = new Button();
        private readonly Button selectDevButton = new Button();
        private readonly Button refreshButton = new Button();
        private readonly Button rollbackButton = new Button();

        public MainForm()
        {
            baseDirectory = AppDomain.CurrentDomain.BaseDirectory;
            actionScript = Path.Combine(baseDirectory, "scripts", "Invoke-BarClientLauncher.ps1");
            pveScript = Path.Combine(baseDirectory, "scripts", "Invoke-BarPveMode.ps1");
            string serverPath = Path.Combine(baseDirectory, "server.json");
            if (!File.Exists(serverPath) || !File.Exists(actionScript) || !File.Exists(pveScript))
                throw new FileNotFoundException("启动器文件不完整，请重新解压整个文件夹。");

            server = new JavaScriptSerializer().Deserialize<ServerConfig>(File.ReadAllText(serverPath, Encoding.UTF8));
            if (server == null || String.IsNullOrWhiteSpace(server.lobby_host) || server.lobby_port < 1 || server.lobby_port > 65535)
                throw new InvalidDataException("server.json 中的大厅地址无效。");

            Text = "BAR 版本启动器";
            ClientSize = new Size(690, 470);
            MinimumSize = new Size(650, 500);
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Microsoft YaHei UI", 9F);

            Label title = new Label { Text = "Beyond All Reason", Font = new Font(Font.FontFamily, 18F, FontStyle.Bold), AutoSize = true, Location = new Point(24, 16) };
            Label endpoint = new Label { Text = String.Format("大厅：{0}:{1}    房间：{2}", server.lobby_host, server.lobby_port, server.room_name), AutoSize = true, Location = new Point(27, 57) };
            Label pathLabel = new Label { Text = "BAR 客户端配置：", AutoSize = true, Location = new Point(27, 90) };
            configPath.Location = new Point(27, 113);
            configPath.Size = new Size(530, 28);
            configPath.ReadOnly = true;
            selectButton.Text = "选择…";
            selectButton.Location = new Point(570, 111);
            selectButton.Size = new Size(88, 30);

            Label modeLabel = new Label { Text = "游戏版本：", AutoSize = true, Location = new Point(27, 158) };
            modeSelect.Location = new Point(105, 154);
            modeSelect.Size = new Size(200, 30);
            modeSelect.DropDownStyle = ComboBoxStyle.DropDownList;
            modeSelect.Items.AddRange(new object[] { "官方版", "PVE 版", "开发版" });
            modeSelect.SelectedIndex = 0;

            connectButton.Location = new Point(27, 205);
            connectButton.Size = new Size(185, 44);
            restoreButton.Text = "恢复官方服务器";
            restoreButton.Location = new Point(225, 205);
            restoreButton.Size = new Size(165, 44);
            refreshButton.Text = "刷新状态";
            refreshButton.Location = new Point(403, 205);
            refreshButton.Size = new Size(130, 44);

            devLabel.Text = "开发源码：";
            devLabel.AutoSize = true;
            devLabel.Location = new Point(27, 275);
            devPath.Location = new Point(105, 270);
            devPath.Size = new Size(452, 28);
            devPath.ReadOnly = true;
            devPath.Text = server.dev_source ?? String.Empty;
            selectDevButton.Text = "选择…";
            selectDevButton.Location = new Point(570, 269);
            selectDevButton.Size = new Size(88, 30);

            rollbackLabel.Text = "历史版本：";
            rollbackLabel.AutoSize = true;
            rollbackLabel.Location = new Point(27, 327);
            rollbackVersions.Location = new Point(105, 322);
            rollbackVersions.Size = new Size(200, 28);
            rollbackVersions.DropDownStyle = ComboBoxStyle.DropDownList;
            rollbackButton.Text = "回退 PVE";
            rollbackButton.Location = new Point(320, 321);
            rollbackButton.Size = new Size(120, 32);

            status.Location = new Point(27, 385);
            status.Size = new Size(630, 70);
            status.Text = "正在查找 BAR 客户端…";

            Controls.AddRange(new Control[] { title, endpoint, pathLabel, configPath, selectButton,
                modeLabel, modeSelect, connectButton, restoreButton, refreshButton, devLabel, devPath,
                selectDevButton, rollbackLabel, rollbackVersions, rollbackButton, status });
            selectButton.Click += SelectConfig;
            selectDevButton.Click += SelectDevSource;
            refreshButton.Click += async delegate { await RefreshStatusAsync(); };
            connectButton.Click += async delegate { await ConnectAndStartAsync(); };
            restoreButton.Click += async delegate { await RestoreOfficialAsync(); };
            rollbackButton.Click += async delegate { await RollbackPveAsync(); };
            modeSelect.SelectedIndexChanged += async delegate { UpdateMode(); await RefreshStatusAsync(); };
            UpdateMode();
            Shown += async delegate
            {
                string found = FindConfig();
                if (found != null) configPath.Text = found;
                await RefreshStatusAsync();
            };
        }

        private string FindConfig()
        {
            var candidates = new List<string>();
            string profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            AddCandidate(candidates, Path.Combine(profile, "Documents", "My Games", "Beyond All Reason", "chobby_config.json"));
            AddCandidate(candidates, Path.Combine(profile, "Documents", "My Games", "BAR", "chobby_config.json"));
            AddCandidate(candidates, Path.Combine(local, "Programs", "Beyond All Reason", "data", "chobby_config.json"));
            AddCandidate(candidates, Path.Combine(local, "Programs", "beyond-all-reason", "data", "chobby_config.json"));
            AddCandidate(candidates, Path.Combine(local, "Beyond All Reason", "data", "chobby_config.json"));

            string[] relatives = {
                @"BAR\Beyond-All-Reason\data\chobby_config.json",
                @"BeyondAllReason\Beyond-All-Reason\data\chobby_config.json",
                @"Beyond-All-Reason\data\chobby_config.json",
                @"Games\Beyond-All-Reason\data\chobby_config.json"
            };
            foreach (DriveInfo drive in DriveInfo.GetDrives())
            {
                if (drive.DriveType != DriveType.Fixed || !drive.IsReady) continue;
                foreach (string relative in relatives) AddCandidate(candidates, Path.Combine(drive.RootDirectory.FullName, relative));
            }
            return candidates.FirstOrDefault();
        }

        private static void AddCandidate(List<string> values, string path)
        {
            try { if (File.Exists(path) && !values.Contains(path, StringComparer.OrdinalIgnoreCase)) values.Add(path); }
            catch { }
        }

        private void SelectConfig(object sender, EventArgs e)
        {
            using (OpenFileDialog dialog = new OpenFileDialog())
            {
                dialog.Title = "选择 BAR 的 chobby_config.json";
                dialog.Filter = "chobby_config.json|chobby_config.json|JSON 文件 (*.json)|*.json";
                dialog.FileName = "chobby_config.json";
                if (dialog.ShowDialog(this) == DialogResult.OK) configPath.Text = dialog.FileName;
            }
        }

        private async Task RefreshStatusAsync()
        {
            if (!ValidateConfigPath(false)) return;
            SetBusy(true, "正在读取版本状态…");
            if (modeSelect.SelectedIndex == 1)
            {
                CommandResult result = await RunPveActionAsync("Status", null);
                if (result.ExitCode != 0) { SetBusy(false, FriendlyError(result)); return; }
                try
                {
                    var data = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(result.Output.Trim());
                    var serverStatus = (Dictionary<string, object>)data["server"];
                    string gameName = Convert.ToString(serverStatus["gameName"]);
                    rollbackVersions.Items.Clear();
                    foreach (object item in (IEnumerable)data["history"])
                    {
                        var entry = item as Dictionary<string, object>;
                        if (entry != null && entry.ContainsKey("version"))
                            rollbackVersions.Items.Add(Convert.ToString(entry["version"]));
                    }
                    if (rollbackVersions.Items.Count > 0) rollbackVersions.SelectedIndex = 0;
                    var active = data["active"] as Dictionary<string, object>;
                    string local = active == null ? "未安装" : Convert.ToString(active["gameName"]);
                    bool ready = data.ContainsKey("ready") && Convert.ToBoolean(data["ready"]);
                    string reason = data.ContainsKey("reason") ? Convert.ToString(data["reason"]) : "服务器状态未知。";
                    SetBusy(false, "服务器：" + gameName + "    本机：" + local + (ready ? "\n可进入 PVE 房间。" : "\n" + reason));
                }
                catch (Exception ex) { SetBusy(false, "PVE 状态格式无效：" + ex.Message); }
                return;
            }
            CommandResult normal = await RunActionAsync("GetServerStatus");
            SetBusy(false, normal.ExitCode == 0 ? DescribeState(normal.Output) : FriendlyError(normal));
        }

        private async Task ConnectAndStartAsync()
        {
            if (!ValidateConfigPath(true)) return;
            if (modeSelect.SelectedIndex == 2)
            {
                SetBusy(true, "正在以隔离目录启动本地开发版…");
                CommandResult developed = await RunPveActionAsync("LaunchDev", null);
                SetBusy(false, developed.ExitCode == 0 ? "开发版测试会话已结束。" : FriendlyError(developed));
                return;
            }
            if (modeSelect.SelectedIndex == 0)
            {
                SetBusy(true, "正在恢复官方大厅设置…");
                CommandResult restored = await RunActionAsync("RestoreOfficialServer");
                if (restored.ExitCode != 0) { SetBusy(false, FriendlyError(restored)); return; }
                status.Text = "正在启动官方 BAR…";
                CommandResult official = await RunActionAsync("StartGame");
                SetBusy(false, official.ExitCode == 0 ? "官方 BAR 已启动。" : FriendlyError(official));
                return;
            }

            SetBusy(true, "正在检查服务器版本并更新 PVE 游戏包…");
            CommandResult prepared = await RunPveActionAsync("PreparePve", null);
            if (prepared.ExitCode != 0) { SetBusy(false, FriendlyError(prepared)); return; }
            status.Text = "PVE 包已校验。正在切换私人大厅…";
            CommandResult switched = await RunActionAsync("SwitchToPrivateServer");
            if (switched.ExitCode != 0) { SetBusy(false, FriendlyError(switched)); return; }
            status.Text = "正在启动 BAR；请在房间中确认游戏名为 BAR PVE。";
            CommandResult started = await RunActionAsync("StartGame");
            SetBusy(false, started.ExitCode == 0 ? "PVE 会话已结束。游戏包已保留，可供回退。" : FriendlyError(started));
        }

        private async Task RestoreOfficialAsync()
        {
            if (!ValidateConfigPath(true)) return;
            SetBusy(true, "正在恢复切换前的官方配置…");
            CommandResult result = await RunActionAsync("RestoreOfficialServer");
            SetBusy(false, result.ExitCode == 0 ? "官方服务器配置已恢复。" : FriendlyError(result));
        }

        private void SelectDevSource(object sender, EventArgs e)
        {
            using (FolderBrowserDialog dialog = new FolderBrowserDialog())
            {
                dialog.Description = "选择 BAR-PVE Git 工作树";
                if (Directory.Exists(devPath.Text)) dialog.SelectedPath = devPath.Text;
                if (dialog.ShowDialog(this) == DialogResult.OK) devPath.Text = dialog.SelectedPath;
            }
        }

        private void UpdateMode()
        {
            bool pve = modeSelect.SelectedIndex == 1;
            bool dev = modeSelect.SelectedIndex == 2;
            connectButton.Text = pve ? "更新并进入 PVE" : (dev ? "运行开发版" : "启动官方 BAR");
            devLabel.Visible = devPath.Visible = selectDevButton.Visible = dev;
            rollbackLabel.Visible = rollbackVersions.Visible = rollbackButton.Visible = pve;
        }

        private async Task RollbackPveAsync()
        {
            if (!ValidateConfigPath(true)) return;
            if (rollbackVersions.SelectedItem == null) { status.Text = "没有可回退的历史版本。"; return; }
            SetBusy(true, "正在验证并回退 PVE 游戏包…");
            CommandResult result = await RunPveActionAsync("RollbackPve", Convert.ToString(rollbackVersions.SelectedItem));
            SetBusy(false, result.ExitCode == 0 ? "PVE 已回退到所选版本；联机前会再次对齐服务器版本。" : FriendlyError(result));
            if (result.ExitCode == 0) await RefreshStatusAsync();
        }

        private bool ValidateConfigPath(bool showDialog)
        {
            bool valid = File.Exists(configPath.Text) && String.Equals(Path.GetFileName(configPath.Text), "chobby_config.json", StringComparison.OrdinalIgnoreCase);
            if (!valid)
            {
                status.Text = "未找到 BAR 客户端。请点“选择…”并选择 BAR data 目录中的 chobby_config.json。";
                if (showDialog) SelectConfig(this, EventArgs.Empty);
            }
            return File.Exists(configPath.Text) && String.Equals(Path.GetFileName(configPath.Text), "chobby_config.json", StringComparison.OrdinalIgnoreCase);
        }

        private void SetBusy(bool busy, string message)
        {
            connectButton.Enabled = restoreButton.Enabled = refreshButton.Enabled = selectButton.Enabled =
                selectDevButton.Enabled = rollbackButton.Enabled = modeSelect.Enabled = rollbackVersions.Enabled = !busy;
            status.Text = message;
            UseWaitCursor = busy;
        }

        private string DescribeState(string json)
        {
            try
            {
                var data = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(json.Trim());
                string state = data.ContainsKey("state") ? Convert.ToString(data["state"]) : "unknown";
                if (state == "private") return "当前状态：已切换到 BAR Custom Test。可以直接连接并启动。";
                if (state == "official") return "当前状态：官方服务器。点击“连接并启动 BAR”会先创建备份，再切换。";
                return "当前配置状态无法确认。请先恢复官方配置或重新选择 chobby_config.json。";
            }
            catch { return "状态命令已完成，但返回内容无法解析。"; }
        }

        private string FriendlyError(CommandResult result)
        {
            string value = String.IsNullOrWhiteSpace(result.Error) ? result.Output : result.Error;
            if (String.IsNullOrWhiteSpace(value)) value = "命令失败，退出代码 " + result.ExitCode;
            return value.Trim();
        }

        private Task<CommandResult> RunActionAsync(string action)
        {
            return Task.Run(delegate
            {
                string command = String.Format("& '{0}' -Action '{1}' -ConfigPath '{2}' -LobbyHost '{3}' -LobbyPort {4} -ServerName '{5}'",
                    Quote(actionScript), Quote(action), Quote(configPath.Text), Quote(server.lobby_host), server.lobby_port, Quote(server.server_name));
                string encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(command));
                var info = new ProcessStartInfo
                {
                    FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe"),
                    Arguments = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand " + encoded,
                    WorkingDirectory = baseDirectory,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                using (Process process = Process.Start(info))
                {
                    string output = process.StandardOutput.ReadToEnd();
                    string error = process.StandardError.ReadToEnd();
                    process.WaitForExit();
                    return new CommandResult { ExitCode = process.ExitCode, Output = output, Error = error };
                }
            });
        }

        private Task<CommandResult> RunPveActionAsync(string action, string version)
        {
            return Task.Run(delegate
            {
                string command = String.Format("& '{0}' -Action '{1}' -ConfigPath '{2}' -StatusSource '{3}' -DevSource '{4}' -Version '{5}' -DevEngineVersion '{6}'",
                    Quote(pveScript), Quote(action), Quote(configPath.Text), Quote(server.pve_status_source),
                    Quote(devPath.Text), Quote(version), Quote(String.IsNullOrWhiteSpace(server.dev_engine_version) ? "2026.07.04" : server.dev_engine_version));
                string encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(command));
                var info = new ProcessStartInfo
                {
                    FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe"),
                    Arguments = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand " + encoded,
                    WorkingDirectory = baseDirectory,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                using (Process process = Process.Start(info))
                {
                    string output = process.StandardOutput.ReadToEnd();
                    string error = process.StandardError.ReadToEnd();
                    process.WaitForExit();
                    return new CommandResult { ExitCode = process.ExitCode, Output = output, Error = error };
                }
            });
        }

        private static string Quote(string value) { return (value ?? String.Empty).Replace("'", "''"); }
    }

    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try { Application.Run(new MainForm()); }
            catch (Exception ex) { MessageBox.Show(ex.Message, "BAR Custom Test 连接器", MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }
    }
}
