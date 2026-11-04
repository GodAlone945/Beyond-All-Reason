using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Net.Sockets;
using System.Runtime.InteropServices;
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

    internal static class Theme
    {
        public static readonly Color Ink = Color.FromArgb(11, 13, 17);
        public static readonly Color Surface = Color.FromArgb(22, 25, 32);
        public static readonly Color SurfaceTop = Color.FromArgb(28, 32, 40);
        public static readonly Color Field = Color.FromArgb(15, 18, 23);
        public static readonly Color FieldHover = Color.FromArgb(21, 25, 31);
        public static readonly Color Gold = Color.FromArgb(209, 167, 92);
        public static readonly Color GoldLight = Color.FromArgb(246, 226, 174);
        public static readonly Color GoldDim = Color.FromArgb(110, 209, 167, 92);
        public static readonly Color Text = Color.FromArgb(237, 234, 227);
        public static readonly Color Muted = Color.FromArgb(146, 154, 165);
        public static readonly Color Border = Color.FromArgb(42, 47, 57);

        public static readonly Font BrandFont = new Font("Microsoft YaHei UI", 31F, FontStyle.Bold);
        public static readonly Font TitleFont = new Font("Microsoft YaHei UI", 15F, FontStyle.Bold);
        public static readonly Font SubFont = new Font("Microsoft YaHei UI", 9F, FontStyle.Bold);
        public static readonly Font SectionFont = new Font("Microsoft YaHei UI", 10F, FontStyle.Bold);
        public static readonly Font BodyFont = new Font("Microsoft YaHei UI", 9F);
        public static readonly Font EmphFont = new Font("Microsoft YaHei UI", 10F, FontStyle.Bold);
        public static readonly Font HintFont = new Font("Microsoft YaHei UI", 8.25F);
        public static readonly Font ChipFont = new Font("Consolas", 8F, FontStyle.Bold);
        public static readonly Font MonoFont = new Font("Consolas", 9F);
        public static readonly Font ButtonFont = new Font("Microsoft YaHei UI", 9.5F, FontStyle.Bold);

        public static GraphicsPath Round(Rectangle bounds, int radius)
        {
            GraphicsPath path = new GraphicsPath();
            if (radius <= 0)
            {
                path.AddRectangle(bounds);
                return path;
            }
            int d = radius * 2;
            path.AddArc(bounds.X, bounds.Y, d, d, 180F, 90F);
            path.AddArc(bounds.Right - d, bounds.Y, d, d, 270F, 90F);
            path.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0F, 90F);
            path.AddArc(bounds.X, bounds.Bottom - d, d, d, 90F, 90F);
            path.CloseFigure();
            return path;
        }
    }

    internal sealed class Card : Panel
    {
        public string Index = String.Empty;
        public string Title = String.Empty;
        public int Radius = 12;

        public Card()
        {
            DoubleBuffered = true;
            BackColor = Theme.Ink;
            Margin = new Padding(0, 0, 0, 14);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            PaintFace(e.Graphics);
        }

        public void PaintFace(Graphics g)
        {
            g.Clear(BackColor);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
            using (GraphicsPath path = Theme.Round(r, Radius))
            {
                using (SolidBrush fill = new SolidBrush(Theme.Surface)) g.FillPath(fill, path);
                using (Pen pen = new Pen(Theme.Border)) g.DrawPath(pen, path);
            }

            if (String.IsNullOrEmpty(Index) && String.IsNullOrEmpty(Title)) return;
            Rectangle chip = new Rectangle(20, 16, 33, 20);
            using (GraphicsPath path = Theme.Round(chip, 5))
            {
                using (SolidBrush fill = new SolidBrush(Color.FromArgb(24, Theme.Gold))) g.FillPath(fill, path);
                using (Pen pen = new Pen(Theme.GoldDim)) g.DrawPath(pen, path);
            }
            TextRenderer.DrawText(g, Index, Theme.ChipFont, chip, Theme.Gold,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            TextRenderer.DrawText(g, Title, Theme.SectionFont, new Point(64, 16), Theme.Text);
        }
    }

    internal sealed class Pill : Button
    {
        public bool Primary;
        public bool Selected;
        public bool AlignLeft;
        public bool ShowCaret;
        public int Radius = 8;
        private bool hover;

        public Pill()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            UseVisualStyleBackColor = false;
            Font = Theme.ButtonFont;
            Cursor = Cursors.Hand;
            TabStop = false;
        }

        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            Color around = Theme.Ink;
            if (Parent is Card) around = Theme.Surface;
            else if (Parent != null && Parent.BackColor != Color.Transparent) around = Parent.BackColor;
            g.Clear(around);
            g.SmoothingMode = SmoothingMode.AntiAlias;

            Color fill, border, text;
            if (!Enabled)
            {
                fill = Theme.Field; border = Theme.Border; text = Color.FromArgb(104, Theme.Muted);
            }
            else if (Primary)
            {
                fill = hover ? Theme.GoldLight : Theme.Gold;
                border = fill;
                text = Color.FromArgb(18, 15, 9);
            }
            else if (Selected)
            {
                fill = Color.FromArgb(52, 44, 30);
                border = Theme.Gold;
                text = Theme.GoldLight;
            }
            else
            {
                fill = hover ? Theme.FieldHover : Theme.Field;
                border = hover ? Theme.GoldDim : Theme.Border;
                text = hover ? Theme.GoldLight : Theme.Text;
            }

            Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
            using (GraphicsPath path = Theme.Round(r, Radius))
            {
                using (SolidBrush brush = new SolidBrush(fill)) g.FillPath(brush, path);
                using (Pen pen = new Pen(border)) g.DrawPath(pen, path);
            }

            TextRenderer.DrawText(g, Text, Font, AlignLeft ? new Rectangle(15, 0, Width - (ShowCaret ? 34 : 24), Height) : r, text,
                AlignLeft ? (TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis)
                    : (TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis));

            if (ShowCaret)
            {
                int cx = Width - 17;
                int cy = Height / 2;
                using (Pen pen = new Pen(text, 1.6F))
                {
                    pen.StartCap = LineCap.Round;
                    pen.EndCap = LineCap.Round;
                    g.DrawLines(pen, new Point[] { new Point(cx - 5, cy - 1), new Point(cx, cy + 4), new Point(cx + 5, cy - 1) });
                }
            }
        }
    }

    internal sealed class FieldBox : Panel
    {
        public readonly TextBox Box;

        public FieldBox(TextBox box)
        {
            DoubleBuffered = true;
            BackColor = Theme.Surface;
            Box = box;
            box.BorderStyle = BorderStyle.None;
            box.BackColor = Theme.Field;
            box.ForeColor = Theme.Text;
            box.Font = Theme.MonoFont;
            box.HideSelection = true;
            Controls.Add(box);
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            Box.Location = new Point(12, Math.Max(0, (Height - Box.Height) / 2));
            Box.Width = Math.Max(20, Width - 24);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(BackColor);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
            using (GraphicsPath path = Theme.Round(r, 8))
            {
                using (SolidBrush fill = new SolidBrush(Theme.Field)) g.FillPath(fill, path);
                using (Pen pen = new Pen(Theme.Border)) g.DrawPath(pen, path);
            }
        }
    }

    internal sealed class DarkColorTable : ProfessionalColorTable
    {
        public override Color ToolStripDropDownBackground { get { return Theme.Surface; } }
        public override Color ImageMarginGradientBegin { get { return Theme.Surface; } }
        public override Color ImageMarginGradientMiddle { get { return Theme.Surface; } }
        public override Color ImageMarginGradientEnd { get { return Theme.Surface; } }
        public override Color MenuBorder { get { return Theme.Border; } }
        public override Color MenuItemBorder { get { return Theme.Gold; } }
        public override Color MenuItemSelected { get { return Color.FromArgb(50, 42, 29); } }
        public override Color MenuItemSelectedGradientBegin { get { return Color.FromArgb(50, 42, 29); } }
        public override Color MenuItemSelectedGradientEnd { get { return Color.FromArgb(50, 42, 29); } }
        public override Color SeparatorDark { get { return Theme.Border; } }
        public override Color SeparatorLight { get { return Theme.Border; } }
    }

    internal sealed class DarkMenuRenderer : ToolStripProfessionalRenderer
    {
        public DarkMenuRenderer() : base(new DarkColorTable()) { RoundedEdges = false; }

        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            e.TextColor = e.Item.Selected ? Theme.GoldLight : Theme.Text;
            base.OnRenderItemText(e);
        }
    }

    internal sealed class MainForm : Form
    {
        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr handle, int attribute, ref int value, int size);

        private const int HeaderHeight = 124;
        private const int FooterHeight = 120;
        private const int CardOneRow = 158;
        private const int CardTwoRow = 126;
        private const int CardThreeRow = 126;
        private const int ActionRow = 76;

        private readonly string baseDirectory;
        private readonly string actionScript;
        private readonly string pveScript;
        private readonly ServerConfig server;
        private readonly TextBox configPath = new TextBox();
        private readonly TextBox devPath = new TextBox();
        private readonly ComboBox modeSelect = new ComboBox();
        private readonly CheckBox roguelikeDev = new CheckBox();
        private readonly Button[] modeButtons = new Button[3];
        private readonly Button rollbackPicker = new Pill();
        private readonly List<string> rollbackVersions = new List<string>();
        private string rollbackChoice;
        private readonly Label devLabel = new Label();
        private readonly Label rollbackLabel = new Label();
        private readonly TextBox status = new TextBox();
        private readonly Button connectButton = new Pill();
        private readonly Button restoreButton = new Pill();
        private readonly Button selectButton = new Pill();
        private readonly Button selectDevButton = new Pill();
        private readonly Button refreshButton = new Pill();
        private readonly Button rollbackButton = new Pill();
        private readonly Card extraCard = new Card();
        private readonly Panel devRow = new Panel();
        private readonly Panel rollbackRow = new Panel();
        private readonly Label modeDescription = new Label();
        private readonly Label modeHint = new Label();
        private readonly TableLayoutPanel contentStack = new TableLayoutPanel();
        private Panel console;
        private bool busy;
        private bool extraVisible;

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            int enabled = 1;
            try
            {
                if (DwmSetWindowAttribute(Handle, 20, ref enabled, sizeof(int)) != 0)
                    DwmSetWindowAttribute(Handle, 19, ref enabled, sizeof(int));
            }
            catch (DllNotFoundException) { }
            catch (EntryPointNotFoundException) { }

            try
            {
                int round = 2;
                DwmSetWindowAttribute(Handle, 33, ref round, sizeof(int));
                int caption = Color.FromArgb(18, 21, 27).ToArgb() & 0x00FFFFFF;
                DwmSetWindowAttribute(Handle, 35, ref caption, sizeof(int));
                int captionText = Theme.Text.ToArgb() & 0x00FFFFFF;
                DwmSetWindowAttribute(Handle, 36, ref captionText, sizeof(int));
            }
            catch (DllNotFoundException) { }
            catch (EntryPointNotFoundException) { }
        }

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
            ClientSize = new Size(860, 646);
            MinimumSize = new Size(760, 620);
            StartPosition = FormStartPosition.CenterScreen;
            Font = Theme.BodyFont;
            AutoScaleMode = AutoScaleMode.Dpi;
            BackColor = Theme.Ink;
            ForeColor = Theme.Text;
            DoubleBuffered = true;

            Panel header = new Panel { Dock = DockStyle.Fill, BackColor = Theme.SurfaceTop, Margin = Padding.Empty };
            header.Paint += PaintHeader;
            Label brand = new Label { Text = "BAR", Font = Theme.BrandFont, ForeColor = Theme.GoldLight,
                BackColor = Color.Transparent, Location = new Point(26, 26), Size = new Size(120, 62) };
            Label title = new Label { Text = "BEYOND ALL REASON", Font = Theme.TitleFont, ForeColor = Theme.Text,
                BackColor = Color.Transparent, Location = new Point(170, 28), Size = new Size(420, 30) };
            Label subtitle = new Label { Text = "PVE  战术部署中心", Font = Theme.SubFont, ForeColor = Theme.Gold,
                BackColor = Color.Transparent, Location = new Point(172, 60), Size = new Size(300, 22) };
            Label endpoint = new Label { Text = String.Format("大厅  {0}:{1}       房间  {2}", server.lobby_host, server.lobby_port, server.room_name),
                ForeColor = Theme.Muted, BackColor = Color.Transparent, Location = new Point(172, 88), Size = new Size(600, 20),
                Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Right };
            header.Controls.AddRange(new Control[] { brand, title, subtitle, endpoint });

            Panel footer = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Ink, Margin = Padding.Empty };
            footer.Paint += PaintFooter;
            Label statusHeading = new Label { Text = "系统状态", Font = new Font(Theme.BodyFont.FontFamily, 9F, FontStyle.Bold),
                ForeColor = Theme.Gold, BackColor = Color.Transparent, Location = new Point(24, 16), Size = new Size(72, 20) };
            Label statusCaption = new Label { Text = "/  STATUS", Font = Theme.HintFont, ForeColor = Theme.Muted,
                BackColor = Color.Transparent, Location = new Point(94, 18), Size = new Size(120, 18) };

            console = new Panel { Location = new Point(24, 46), Size = new Size(ClientSize.Width - 48, 62), BackColor = Theme.Ink,
                Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Right };
            console.Paint += PaintConsole;

            status.Location = new Point(12, 10);
            status.Size = new Size(console.Width + 6, console.Height - 20);
            status.ForeColor = Theme.Text;
            status.BackColor = Theme.Field;
            status.BorderStyle = BorderStyle.None;
            status.Font = Theme.BodyFont;
            status.ReadOnly = true;
            status.Multiline = true;
            status.WordWrap = true;
            status.ScrollBars = ScrollBars.Vertical;
            status.TabStop = false;
            status.Text = "正在查找 BAR 客户端…";
            console.Controls.Add(status);
            console.Resize += delegate
            {
                status.Width = console.Width + 6;
                status.Height = console.Height - 20;
            };
            footer.Controls.AddRange(new Control[] { statusHeading, statusCaption, console });

            Panel body = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Ink, AutoScroll = true,
                Padding = new Padding(24, 20, 24, 20) };
            contentStack.Dock = DockStyle.Top;
            contentStack.ColumnCount = 1;
            contentStack.RowCount = 4;
            contentStack.Height = CardOneRow + CardTwoRow + ActionRow;
            contentStack.Margin = Padding.Empty;
            contentStack.Padding = Padding.Empty;
            contentStack.BackColor = Theme.Ink;
            contentStack.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            contentStack.RowStyles.Add(new RowStyle(SizeType.Absolute, CardOneRow));
            contentStack.RowStyles.Add(new RowStyle(SizeType.Absolute, CardTwoRow));
            contentStack.RowStyles.Add(new RowStyle(SizeType.Absolute, 0F));
            contentStack.RowStyles.Add(new RowStyle(SizeType.Absolute, ActionRow));

            Card modeCard = CreateCard("01", "选择游戏环境");
            int segmentWidth = 104;
            string[] modes = new string[] { "官方版", "PVE 版", "开发版" };
            for (int i = 0; i < 3; i++)
            {
                Pill segment = new Pill { Text = modes[i], Location = new Point(20 + i * (segmentWidth + 8), 52),
                    Size = new Size(segmentWidth, 40), Radius = 8 };
                int index = i;
                segment.Click += delegate { modeSelect.SelectedIndex = index; };
                modeButtons[i] = segment;
                modeCard.Controls.Add(segment);
            }

            modeSelect.Visible = false;
            modeSelect.Items.AddRange(new object[] { "官方版", "PVE 版", "开发版" });
            modeSelect.SelectedIndex = 0;
            modeCard.Controls.Add(modeSelect);

            modeDescription.Location = new Point(372, 58);
            modeDescription.Size = new Size(300, 28);
            modeDescription.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            modeDescription.ForeColor = Theme.Text;
            modeDescription.BackColor = Color.Transparent;
            modeDescription.Font = Theme.EmphFont;
            modeHint.Location = new Point(22, 106);
            modeHint.Size = new Size(700, 20);
            modeHint.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            modeHint.ForeColor = Theme.Muted;
            modeHint.BackColor = Color.Transparent;
            modeHint.Font = Theme.HintFont;
            modeCard.Controls.AddRange(new Control[] { modeDescription, modeHint });
            roguelikeDev.Text = "Roguelike 模式";
            roguelikeDev.Location = new Point(22, 128);
            roguelikeDev.Size = new Size(150, 20);
            roguelikeDev.ForeColor = Theme.Text;
            roguelikeDev.BackColor = Color.Transparent;
            roguelikeDev.Font = Theme.HintFont;
            modeCard.Controls.Add(roguelikeDev);

            Card clientCard = CreateCard("02", "BAR 客户端配置");
            clientCard.Size = new Size(812, 112);
            FieldBox configField = new FieldBox(configPath);
            configField.Location = new Point(20, 48);
            configField.Size = new Size(666, 38);
            configPath.ReadOnly = true;
            configPath.TabStop = false;
            selectButton.Text = "浏览…";
            selectButton.Location = new Point(696, 48);
            selectButton.Size = new Size(96, 38);
            StyleButton(selectButton, false);
            clientCard.Resize += delegate
            {
                selectButton.Left = Math.Max(120, clientCard.ClientSize.Width - 20 - selectButton.Width);
                configField.Left = 20;
                configField.Width = Math.Max(160, selectButton.Left - 30);
            };
            clientCard.Controls.AddRange(new Control[] { configField, selectButton });

            extraCard.BackColor = Theme.Surface;
            extraCard.Dock = DockStyle.Fill;
            extraCard.Margin = new Padding(0, 0, 0, 14);
            extraCard.Size = new Size(812, 112);
            extraCard.Index = "03";
            extraCard.Title = "PVE 历史版本";

            devRow.Location = new Point(20, 48);
            devRow.Size = new Size(760, 38);
            devRow.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            devRow.BackColor = Theme.Surface;
            devLabel.Text = "源码目录";
            devLabel.Location = new Point(0, 10);
            devLabel.Size = new Size(62, 22);
            devLabel.ForeColor = Theme.Muted;
            devLabel.Font = Theme.HintFont;
            FieldBox devField = new FieldBox(devPath);
            devField.Location = new Point(66, 0);
            devField.Size = new Size(560, 38);
            devField.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            devPath.ReadOnly = true;
            devPath.TabStop = false;
            devPath.Text = server.dev_source ?? String.Empty;
            selectDevButton.Text = "浏览…";
            selectDevButton.Location = new Point(636, 0);
            selectDevButton.Size = new Size(96, 38);
            selectDevButton.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            StyleButton(selectDevButton, false);
            devRow.Layout += delegate
            {
                selectDevButton.Left = devRow.ClientSize.Width - selectDevButton.Width;
                devField.Left = 66;
                devField.Width = Math.Max(140, selectDevButton.Left - devField.Left - 10);
            };
            devRow.Controls.AddRange(new Control[] { devLabel, devField, selectDevButton });

            rollbackRow.Location = new Point(20, 48);
            rollbackRow.Size = new Size(760, 38);
            rollbackRow.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            rollbackRow.BackColor = Theme.Surface;
            rollbackLabel.Text = "回退到";
            rollbackLabel.Location = new Point(0, 10);
            rollbackLabel.Size = new Size(62, 22);
            rollbackLabel.ForeColor = Theme.Muted;
            rollbackLabel.Font = Theme.HintFont;
            StyleButton(rollbackPicker, false);
            rollbackPicker.Location = new Point(66, 0);
            rollbackPicker.Size = new Size(220, 38);
            rollbackPicker.Font = Theme.MonoFont;
            rollbackPicker.Text = "暂无版本";
            Pill pickerPill = rollbackPicker as Pill;
            if (pickerPill != null) { pickerPill.AlignLeft = true; pickerPill.ShowCaret = true; }
            rollbackPicker.Click += delegate { ShowRollbackMenu(); };
            rollbackButton.Text = "回退所选版本";
            rollbackButton.Location = new Point(298, 0);
            rollbackButton.Size = new Size(148, 38);
            StyleButton(rollbackButton, false);
            rollbackRow.Controls.AddRange(new Control[] { rollbackLabel, rollbackPicker, rollbackButton });
            extraCard.Controls.AddRange(new Control[] { devRow, rollbackRow });
            extraCard.Resize += delegate
            {
                int width = Math.Max(240, extraCard.ClientSize.Width - 40);
                devRow.Width = width;
                rollbackRow.Width = width;
            };

            Panel actions = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Ink, Margin = Padding.Empty,
                Size = new Size(800, ActionRow) };
            connectButton.Location = new Point(0, 8);
            connectButton.Size = new Size(236, 50);
            StyleButton(connectButton, true);
            restoreButton.Text = "恢复官方服务器";
            restoreButton.Location = new Point(248, 8);
            restoreButton.Size = new Size(172, 50);
            StyleButton(restoreButton, false);
            refreshButton.Text = "刷新状态";
            refreshButton.Location = new Point(ClientSize.Width - 48 - 118, 8);
            refreshButton.Size = new Size(118, 50);
            refreshButton.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            StyleButton(refreshButton, false);
            actions.Controls.AddRange(new Control[] { connectButton, restoreButton, refreshButton });
            actions.Resize += delegate
            {
                refreshButton.Left = Math.Max(380, actions.ClientSize.Width - refreshButton.Width);
            };

            contentStack.Controls.Add(modeCard, 0, 0);
            contentStack.Controls.Add(clientCard, 0, 1);
            contentStack.Controls.Add(extraCard, 0, 2);
            contentStack.Controls.Add(actions, 0, 3);
            body.Controls.Add(contentStack);
            TableLayoutPanel shell = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 3,
                Margin = Padding.Empty, Padding = Padding.Empty, BackColor = Theme.Ink };
            shell.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            shell.RowStyles.Add(new RowStyle(SizeType.Absolute, HeaderHeight));
            shell.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            shell.RowStyles.Add(new RowStyle(SizeType.Absolute, FooterHeight));
            header.Margin = body.Margin = footer.Margin = Padding.Empty;
            shell.Controls.Add(header, 0, 0);
            shell.Controls.Add(body, 0, 1);
            shell.Controls.Add(footer, 0, 2);
            Controls.Add(shell);
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

        private static Card CreateCard(string index, string title)
        {
            Card card = new Card { Dock = DockStyle.Fill, Index = index, Title = title };
            return card;
        }

        private static void StyleButton(Button button, bool primary)
        {
            Pill pill = button as Pill;
            if (pill == null) return;
            pill.Primary = primary;
            pill.Invalidate();
        }

        private static void PaintHeader(object sender, PaintEventArgs e)
        {
            Panel header = (Panel)sender;
            Rectangle bounds = header.ClientRectangle;
            if (bounds.Width <= 0 || bounds.Height <= 0) return;

            using (LinearGradientBrush brush = new LinearGradientBrush(bounds, Theme.SurfaceTop, Theme.Ink, 90F))
                e.Graphics.FillRectangle(brush, bounds);

            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            int w = header.Width;
            using (SolidBrush brush = new SolidBrush(Color.FromArgb(22, Theme.Gold)))
            {
                e.Graphics.FillPolygon(brush, new Point[] { new Point(w - 250, 0), new Point(w - 150, 0),
                    new Point(w - 300, header.Height), new Point(w - 400, header.Height) });
            }
            using (SolidBrush brush = new SolidBrush(Color.FromArgb(13, Theme.Gold)))
            {
                e.Graphics.FillPolygon(brush, new Point[] { new Point(w - 110, 0), new Point(w - 60, 0),
                    new Point(w - 210, header.Height), new Point(w - 260, header.Height) });
            }

            using (SolidBrush brush = new SolidBrush(Theme.Border))
                e.Graphics.FillRectangle(brush, 150, 28, 1, 66);

            using (Pen pen = new Pen(Theme.Border))
                e.Graphics.DrawLine(pen, 0, header.Height - 1, header.Width, header.Height - 1);
            using (Pen pen = new Pen(Theme.Gold, 2F))
                e.Graphics.DrawLine(pen, 26, header.Height - 1, 120, header.Height - 1);
        }

        private static void PaintFooter(object sender, PaintEventArgs e)
        {
            Panel footer = (Panel)sender;
            using (Pen pen = new Pen(Theme.Border))
                e.Graphics.DrawLine(pen, 0, 0, footer.Width, 0);
        }

        private static void PaintConsole(object sender, PaintEventArgs e)
        {
            Panel panel = (Panel)sender;
            if (panel.Width <= 2 || panel.Height <= 2) return;
            e.Graphics.Clear(panel.BackColor);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle r = new Rectangle(0, 0, panel.Width - 1, panel.Height - 1);
            using (GraphicsPath path = Theme.Round(r, 8))
            {
                using (SolidBrush fill = new SolidBrush(Theme.Field)) e.Graphics.FillPath(fill, path);
                using (Pen pen = new Pen(Theme.Border)) e.Graphics.DrawPath(pen, path);
            }
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
                    rollbackVersions.Clear();
                    foreach (object item in (IEnumerable)data["history"])
                    {
                        var entry = item as Dictionary<string, object>;
                        if (entry != null && entry.ContainsKey("version"))
                            rollbackVersions.Add(Convert.ToString(entry["version"]));
                    }
                    rollbackChoice = rollbackVersions.Count > 0 ? rollbackVersions[0] : null;
                    UpdateRollbackPicker();
                    var active = data["active"] as Dictionary<string, object>;
                    string local = active == null ? "未安装" : Convert.ToString(active["gameName"]);
                    bool ready = data.ContainsKey("ready") && Convert.ToBoolean(data["ready"]);
                    string reason = data.ContainsKey("reason") ? Convert.ToString(data["reason"]) : "服务器状态未知。";
                    SetBusy(false, "服务器：" + gameName + "    本机：" + local + (ready ? "\r\n可进入 PVE 房间。" : "\r\n" + reason));
                }
                catch (Exception ex) { SetBusy(false, "PVE 状态格式无效：" + ex.Message); }
                return;
            }
            CommandResult normal = await RunActionAsync("GetServerStatus");
            SetBusy(false, normal.ExitCode == 0 ? DescribeState(normal.Output) : FriendlyError(normal));
        }

        private void UpdateRollbackPicker()
        {
            rollbackPicker.Text = rollbackChoice ?? "暂无版本";
            rollbackPicker.Enabled = rollbackVersions.Count > 0 && !busy;
        }

        private void ShowRollbackMenu()
        {
            if (rollbackVersions.Count == 0) return;
            ContextMenuStrip menu = new ContextMenuStrip();
            menu.Renderer = new DarkMenuRenderer();
            menu.ShowImageMargin = false;
            menu.ShowCheckMargin = false;
            menu.BackColor = Theme.Surface;
            menu.ForeColor = Theme.Text;
            menu.Font = Theme.MonoFont;
            foreach (string version in rollbackVersions)
            {
                string value = version;
                ToolStripMenuItem item = new ToolStripMenuItem(value);
                item.ForeColor = Theme.Text;
                item.Padding = new Padding(6, 4, 8, 4);
                item.Click += delegate { rollbackChoice = value; UpdateRollbackPicker(); };
                menu.Items.Add(item);
            }
            menu.Closed += delegate { menu.Dispose(); };
            menu.Show(rollbackPicker, new Point(0, rollbackPicker.Height + 4));
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
            roguelikeDev.Visible = dev;
            connectButton.Text = pve ? "更新并进入 PVE" : (dev ? "运行开发版" : "启动官方 BAR");
            modeDescription.Text = pve ? "多人 PVE · 对齐服务器版本" : (dev ? "本地开发 · 隔离运行" : "官方游戏 · 原版大厅");
            modeHint.Text = pve ? "自动校验游戏包，进入专属 PVE 房间。" :
                (dev ? "从本地源码启动，不修改正式游戏数据。" : "恢复官方大厅配置，启动已安装的 BAR 客户端。");
            for (int i = 0; i < modeButtons.Length; i++)
            {
                Pill pill = modeButtons[i] as Pill;
                if (pill != null) { pill.Selected = i == modeSelect.SelectedIndex; pill.Invalidate(); }
            }
            extraCard.Visible = pve || dev;
            extraVisible = pve || dev;
            contentStack.RowStyles[2].Height = pve || dev ? CardThreeRow : 0F;
            extraCard.Title = pve ? "PVE 历史版本" : "开发源码位置";
            extraCard.Invalidate();
            devRow.Visible = dev;
            rollbackRow.Visible = pve;
            FitWindow();
        }

        private void FitWindow()
        {
            bool extra = extraVisible;
            int content = CardOneRow + CardTwoRow + (extra ? CardThreeRow : 0) + ActionRow;
            contentStack.Height = content;
            Panel contentBody = contentStack.Parent as Panel;
            if (contentBody != null)
                contentBody.AutoScrollMinSize = new Size(0, content + contentBody.Padding.Vertical);

            if (WindowState != FormWindowState.Normal) return;
            int wanted = HeaderHeight + 40 + content + FooterHeight;
            Rectangle area = Screen.FromControl(this).WorkingArea;
            int height = Math.Min(wanted, area.Height - 40);
            if (ClientSize.Height == height) return;
            ClientSize = new Size(ClientSize.Width, height);
            if (Top + Height > area.Bottom - 8) Top = Math.Max(area.Top + 8, area.Bottom - Height - 8);
        }

        private async Task RollbackPveAsync()
        {
            if (!ValidateConfigPath(true)) return;
            if (rollbackChoice == null) { status.Text = "没有可回退的历史版本。"; return; }
            SetBusy(true, "正在验证并回退 PVE 游戏包…");
            CommandResult result = await RunPveActionAsync("RollbackPve", rollbackChoice);
            SetBusy(false, result.ExitCode == 0 ? "PVE 已回退到所选版本；联机前会再次对齐服务器版本。" : FriendlyError(result));
            if (result.ExitCode == 0) await RefreshStatusAsync();
        }

        private bool ValidateConfigPath(bool showDialog)
        {
            bool valid = File.Exists(configPath.Text) && String.Equals(Path.GetFileName(configPath.Text), "chobby_config.json", StringComparison.OrdinalIgnoreCase);
            if (!valid)
            {
                status.Text = "未找到 BAR 客户端。请点“浏览…”并选择 BAR data 目录中的 chobby_config.json。";
                if (showDialog) SelectConfig(this, EventArgs.Empty);
            }
            return File.Exists(configPath.Text) && String.Equals(Path.GetFileName(configPath.Text), "chobby_config.json", StringComparison.OrdinalIgnoreCase);
        }

        private void SetBusy(bool busy, string message)
        {
            this.busy = busy;
            connectButton.Enabled = restoreButton.Enabled = refreshButton.Enabled = selectButton.Enabled =
                selectDevButton.Enabled = rollbackButton.Enabled = !busy;
            for (int i = 0; i < modeButtons.Length; i++) modeButtons[i].Enabled = !busy;
            rollbackPicker.Enabled = !busy && rollbackVersions.Count > 0;
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
                if (state == "official") return "当前状态：官方服务器。点击“启动官方 BAR”会先创建备份，再切换。";
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
            bool useRoguelike = action == "LaunchDev" && roguelikeDev.Checked;
            return Task.Run(delegate
            {
                string command = String.Format("& '{0}' -Action '{1}' -ConfigPath '{2}' -StatusSource '{3}' -DevSource '{4}' -Version '{5}' -DevEngineVersion '{6}'",
                    Quote(pveScript), Quote(action), Quote(configPath.Text), Quote(server.pve_status_source),
                    Quote(devPath.Text), Quote(version), Quote(String.IsNullOrWhiteSpace(server.dev_engine_version) ? "2026.07.04" : server.dev_engine_version));
                if (useRoguelike) command += " -Roguelike";
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
