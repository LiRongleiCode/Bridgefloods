using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Windows.Forms;

namespace DreamSkin;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new DreamSkinForm());
    }
}

internal sealed record StyleOption(string Label, string Value)
{
    public override string ToString() => Label;
}

internal sealed class DreamSkinForm : Form
{
    private const int ScriptTimeoutMilliseconds = 45_000;
    private readonly TextBox imagePath = new();
    private readonly ComboBox stylePicker = new();
    private readonly Label status = new();
    private readonly Button applyButton = new();
    private readonly Button restoreButton = new();
    private readonly string themeDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "CodexDreamSkin",
        "theme");

    public DreamSkinForm()
    {
        Text = "Dream Skin";
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(660, 390);
        Padding = new Padding(24);
        BackColor = Color.FromArgb(246, 248, 251);
        Font = new Font("Microsoft YaHei UI", 10F, FontStyle.Regular, GraphicsUnit.Point);

        BuildUi();
        LoadCurrentTheme();
    }

    private void BuildUi()
    {
        var title = new Label
        {
            AutoSize = true,
            Text = "Dream Skin",
            Font = new Font(Font, FontStyle.Bold),
            ForeColor = Color.FromArgb(15, 23, 42),
            Location = new Point(24, 20),
        };
        Controls.Add(title);

        var subtitle = new Label
        {
            AutoSize = true,
            Text = "选择一张图片和界面风格，应用到 Codex。不会修改官方安装包。",
            ForeColor = Color.FromArgb(71, 85, 105),
            Location = new Point(24, 54),
        };
        Controls.Add(subtitle);

        var imageLabel = new Label
        {
            AutoSize = true,
            Text = "背景图片",
            ForeColor = Color.FromArgb(30, 41, 59),
            Location = new Point(24, 106),
        };
        Controls.Add(imageLabel);

        imagePath.Location = new Point(24, 132);
        imagePath.Size = new Size(494, 30);
        imagePath.ReadOnly = true;
        imagePath.BackColor = Color.White;
        imagePath.BorderStyle = BorderStyle.FixedSingle;
        Controls.Add(imagePath);

        var browseButton = new Button
        {
            Text = "选择图片…",
            Location = new Point(530, 130),
            Size = new Size(106, 34),
            FlatStyle = FlatStyle.Flat,
        };
        browseButton.Click += (_, _) => ChooseImage();
        Controls.Add(browseButton);

        var styleLabel = new Label
        {
            AutoSize = true,
            Text = "背景风格",
            ForeColor = Color.FromArgb(30, 41, 59),
            Location = new Point(24, 190),
        };
        Controls.Add(styleLabel);

        stylePicker.DropDownStyle = ComboBoxStyle.DropDownList;
        stylePicker.Location = new Point(24, 216);
        stylePicker.Size = new Size(300, 30);
        stylePicker.Items.AddRange(new object[]
        {
            new StyleOption("自适应中性（推荐）", "adaptive"),
            new StyleOption("浅色透明玻璃", "light"),
            new StyleOption("深色透明玻璃", "dark"),
        });
        stylePicker.SelectedIndex = 0;
        Controls.Add(stylePicker);

        var hint = new Label
        {
            AutoSize = false,
            Size = new Size(610, 46),
            Text = "自适应模式会读取图片亮度，自动选择深色或浅色文字与玻璃面板。",
            ForeColor = Color.FromArgb(100, 116, 139),
            Location = new Point(24, 258),
        };
        Controls.Add(hint);

        applyButton.Text = "应用主题";
        applyButton.Location = new Point(24, 316);
        applyButton.Size = new Size(128, 38);
        applyButton.FlatStyle = FlatStyle.Flat;
        applyButton.BackColor = Color.FromArgb(30, 41, 59);
        applyButton.ForeColor = Color.White;
        applyButton.Click += async (_, _) => await ApplyThemeAsync();
        Controls.Add(applyButton);

        restoreButton.Text = "恢复原样";
        restoreButton.Location = new Point(166, 316);
        restoreButton.Size = new Size(128, 38);
        restoreButton.FlatStyle = FlatStyle.Flat;
        restoreButton.Click += async (_, _) => await RestoreThemeAsync();
        Controls.Add(restoreButton);

        var openFolder = new LinkLabel
        {
            AutoSize = true,
            Text = "打开主题目录",
            Location = new Point(316, 327),
            LinkColor = Color.FromArgb(51, 65, 85),
        };
        openFolder.Click += (_, _) => OpenThemeDirectory();
        Controls.Add(openFolder);

        status.AutoSize = false;
        status.Size = new Size(610, 24);
        status.Location = new Point(24, 365);
        status.ForeColor = Color.FromArgb(71, 85, 105);
        Controls.Add(status);
    }

    private void LoadCurrentTheme()
    {
        try
        {
            var themePath = Path.Combine(themeDirectory, "theme.json");
            if (!File.Exists(themePath))
            {
                status.Text = "请选择背景图片。";
                return;
            }

            using var document = JsonDocument.Parse(File.ReadAllText(themePath));
            var root = document.RootElement;
            var image = root.TryGetProperty("image", out var imageValue) ? imageValue.GetString() : null;
            var style = root.TryGetProperty("style", out var styleValue) ? styleValue.GetString() : "adaptive";
            if (!string.IsNullOrWhiteSpace(image)) imagePath.Text = Path.Combine(themeDirectory, image);
            SelectStyle(style ?? "adaptive");
            status.Text = "已读取当前主题设置。";
        }
        catch (Exception error)
        {
            status.Text = $"读取主题失败：{error.Message}";
        }
    }

    private void ChooseImage()
    {
        using var dialog = new OpenFileDialog
        {
            Filter = "图片文件 (*.png;*.jpg;*.jpeg;*.webp)|*.png;*.jpg;*.jpeg;*.webp",
            Title = "选择 Dream Skin 背景图片",
            CheckFileExists = true,
            Multiselect = false,
        };

        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            imagePath.Text = dialog.FileName;
            status.Text = $"已选择：{Path.GetFileName(dialog.FileName)}";
        }
    }

    private async Task ApplyThemeAsync()
    {
        if (string.IsNullOrWhiteSpace(imagePath.Text) || !File.Exists(imagePath.Text))
        {
            MessageBox.Show(this, "请先选择一张 PNG、JPG、JPEG 或 WebP 图片。", "Dream Skin", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        try
        {
            applyButton.Enabled = false;
            restoreButton.Enabled = false;
            status.Text = "正在启动 Codex 并应用主题，请稍候…";
            Directory.CreateDirectory(themeDirectory);
            var source = new FileInfo(imagePath.Text);
            if (source.Length == 0 || source.Length > 16 * 1024 * 1024)
            {
                throw new InvalidOperationException("图片必须非空且不超过 16 MB。");
            }

            var extension = source.Extension.ToLowerInvariant();
            if (extension is not ".png" and not ".jpg" and not ".jpeg" and not ".webp")
            {
                throw new InvalidOperationException("只支持 PNG、JPG、JPEG 或 WebP 图片。");
            }

            var destination = Path.Combine(themeDirectory, "background" + extension);
            foreach (var oldImage in Directory.EnumerateFiles(themeDirectory, "background.*"))
            {
                if (!string.Equals(oldImage, destination, StringComparison.OrdinalIgnoreCase))
                    File.Delete(oldImage);
            }
            File.Copy(source.FullName, destination, true);

            var selectedStyle = (StyleOption?)stylePicker.SelectedItem ?? new StyleOption("自适应中性（推荐）", "adaptive");
            var theme = new
            {
                schemaVersion = 1,
                id = "custom",
                name = "My Dream Skin",
                brandSubtitle = selectedStyle.Label,
                style = selectedStyle.Value,
                image = Path.GetFileName(destination),
                promoTitle = "Dream Skin",
                promoSub = selectedStyle.Label,
            };
            var json = JsonSerializer.Serialize(theme, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(Path.Combine(themeDirectory, "theme.json"), json, new UTF8Encoding(false));

            var output = await Task.Run(() => RunPowerShell("start-dream-skin.ps1"));
            if (output.ExitCode != 0)
                throw new InvalidOperationException(output.Error.Length > 0 ? output.Error : output.Output);

            status.Text = "主题已应用。若 Codex 尚未启用 CDP，请先关闭后重新启动。";
        }
        catch (Exception error)
        {
            status.Text = "应用失败。";
            MessageBox.Show(this, error.Message, "Dream Skin", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            applyButton.Enabled = true;
            restoreButton.Enabled = true;
        }
    }

    private async Task RestoreThemeAsync()
    {
        try
        {
            applyButton.Enabled = false;
            restoreButton.Enabled = false;
            status.Text = "正在移除主题，请稍候…";
            var output = await Task.Run(() => RunPowerShell("restore-dream-skin.ps1"));
            if (output.ExitCode != 0)
                throw new InvalidOperationException(output.Error.Length > 0 ? output.Error : output.Output);
            status.Text = "已移除 Dream Skin，Codex 恢复为原始界面。";
        }
        catch (Exception error)
        {
            MessageBox.Show(this, error.Message, "Dream Skin", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            applyButton.Enabled = true;
            restoreButton.Enabled = true;
        }
    }

    private void OpenThemeDirectory()
    {
        Directory.CreateDirectory(themeDirectory);
        Process.Start(new ProcessStartInfo
        {
            FileName = "explorer.exe",
            Arguments = $"\"{themeDirectory}\"",
            UseShellExecute = true,
        });
    }

    private void SelectStyle(string value)
    {
        for (var index = 0; index < stylePicker.Items.Count; index++)
        {
            if (stylePicker.Items[index] is StyleOption option && option.Value == value)
            {
                stylePicker.SelectedIndex = index;
                return;
            }
        }
        stylePicker.SelectedIndex = 0;
    }

    private (int ExitCode, string Output, string Error) RunPowerShell(string scriptName)
    {
        var scriptPath = FindScript(scriptName);
        if (scriptPath is null)
            throw new FileNotFoundException($"找不到 {scriptName}。请把 DreamSkin.exe 放在 windows 目录中。", scriptName);

        var powershell = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
        if (!File.Exists(powershell)) powershell = "powershell.exe";
        var info = new ProcessStartInfo
        {
            FileName = powershell,
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\"",
            WorkingDirectory = Path.GetDirectoryName(scriptPath) ?? AppContext.BaseDirectory,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        using var process = Process.Start(info) ?? throw new InvalidOperationException("无法启动 PowerShell。");
        var outputTask = process.StandardOutput.ReadToEndAsync();
        var errorTask = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(ScriptTimeoutMilliseconds))
        {
            try { process.Kill(entireProcessTree: true); } catch { }
            try { process.WaitForExit(2_000); } catch { }
            return (-1, "", $"脚本在 {ScriptTimeoutMilliseconds / 1000} 秒内没有完成，已停止等待。请确认 Codex 已启动并允许本机 CDP。");
        }
        Task.WaitAll(outputTask, errorTask);
        var output = outputTask.Result;
        var error = errorTask.Result;
        return (process.ExitCode, output.Trim(), error.Trim());
    }

    private static string? FindScript(string scriptName)
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        for (var depth = 0; directory is not null && depth < 10; depth++, directory = directory.Parent)
        {
            var candidate = Path.Combine(directory.FullName, "scripts", scriptName);
            if (File.Exists(candidate)) return candidate;
        }
        return null;
    }
}
