# ====== AYARLAR ======
$GmailUser = "YOURGMAIL.com"               # Gönderen Gmail adresi
$GmailAppPassword = "a f g h o e o j j s u a c s y b"    # Gmail app password (2FA ile oluşturulan)
$To = "RECIPIENTEMAIL@gmail.com"                    # Alıcı adres
$CheckIntervalSec = 5                         # İlk 4624 araması için kontrol aralığı (saniye)
$WindowSeconds = 5                            # İlk tespit aralığı (son kaç saniyeyi kontrol et)
$CaptureInterval = 30                         # Tespit sonrası ekran görüntüsü alma aralığı (saniye)
$SmtpServer = "smtp.gmail.com"
$SmtpPort = 587

# ====== YETKİ KONTROLÜ ======
if (-not ([bool]([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator))) {
    Write-Host "UYARI: Bu script Security loglarını okuyabilmek için yönetici hakları gerektirir. PowerShell'i 'Yönetici olarak çalıştır' şeklinde aç." -ForegroundColor Yellow
    # devam ediyoruz ama Get-WinEvent hata verebilir
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Capture-Screenshot {
    param([string]$OutPath)
    try {
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($bounds.X, $bounds.Y, 0, 0, $bmp.Size)
        $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
        return $true
    } catch {
        Write-Warning "Ekran görüntüsü alınamadı: $_"
        return $false
    }
}

function Send-EmailWithAttachment {
    param(
        [string]$From,
        [string]$To,
        [string]$Subject,
        [string]$Body,
        [string]$AttachmentPath
    )
    try {
        $message = New-Object System.Net.Mail.MailMessage $From, $To, $Subject, $Body
        if (Test-Path $AttachmentPath) {
            $attachment = New-Object System.Net.Mail.Attachment $AttachmentPath
            $message.Attachments.Add($attachment)
        }

        $smtp = New-Object System.Net.Mail.SmtpClient($SmtpServer, $SmtpPort)
        $smtp.EnableSsl = $true
        $smtp.Credentials = New-Object System.Net.NetworkCredential($GmailUser, $GmailAppPassword)
        $smtp.Send($message)

        # temizle
        if ($attachment) { $attachment.Dispose() }
        $message.Dispose()
        return $true
    } catch {
        Write-Warning "E-posta gönderilemedi: $_"
        return $false
    }
}

Write-Host "Başlatıldı. İlk 4624 (başarılı oturum) bekleniyor; tespit edildiğinde her $CaptureInterval saniyede bir ekran görüntüsü alınacak ve e-posta gönderilecek."

# --- İlk 4624 tespiti bekle ---
$initialDetected = $false
while (-not $initialDetected) {
    try {
        $since = (Get-Date).AddSeconds(-$WindowSeconds)
        $filter = @{ LogName = 'Security'; Id = 4624; StartTime = $since }
        $events = Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue

        if ($events -and $events.Count -gt 0) {
            Write-Host "[$(Get-Date)] İlk 4624 tespit edildi. Sürekli yakalama başlıyor..."
            $initialDetected = $true
            break
        } else {
            Write-Host "[$(Get-Date)] Henüz 4624 tespit edilmedi."
        }
    } catch {
        Write-Warning "Arama sırasında hata: $_"
    }
    Start-Sleep -Seconds $CheckIntervalSec
}

# --- Tespit sonrası: her $CaptureInterval saniyede screenshot al ve e-posta gönder ---
while ($true) {
    try {
        $filename = "screenshot_$((Get-Date).ToString('yyyyMMdd_HHmmss')).png"
        $out = Join-Path $env:TEMP $filename

        if (Capture-Screenshot -OutPath $out) {
            $subject = "Periyodik SS: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            $body = "Bu ekran görüntüsü, sistemde en az bir kere başarılı oturum açma (Event ID 4624) tespit edildikten sonra her $CaptureInterval saniyede alınmaktadır.`nZaman: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            if (Send-EmailWithAttachment -From $GmailUser -To $To -Subject $subject -Body $body -AttachmentPath $out) {
                Write-Host "[$(Get-Date)] E-posta gönderildi: $out"
                Remove-Item $out -ErrorAction SilentlyContinue
            } else {
                Write-Warning "E-posta gönderimi başarısız. Ekran görüntüsü kaydedildi: $out"
            }
        }

    } catch {
        Write-Warning "Hata: $_"
    }

    Start-Sleep -Seconds $CaptureInterval
}
