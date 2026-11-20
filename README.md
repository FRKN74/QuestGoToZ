# QuestGoToZ

**World of Warcraft: Forever** *(Midnight Retail tabanlı, Interface `16001`)* için görev yönlendirme, akıllı görev sıralama ve günlük rahatlık addonu.

> **%100 Yasal & Güvenli:** Karakter hareket ettirme, hedefleme, saldırı veya otomatik görev kabul/teslim yapmaz. Yalnızca resmi Blizzard Lua API'leri ile bilgi ve yönlendirme gösterir.

---

## Hızlı Kurulum ve Otomatik Güncelleme (Önerilen)

1. [**Releases**](https://github.com/FRKN74/QuestGoToZ/releases/latest) sayfasından **`QuestGoToZ_Updater.exe`** dosyasını indir ve çalıştır.
2. **Otomatik Ara** veya **Gözat...** ile `World of Warcraft` klasörünü seç *(`_forever_\Interface\AddOns\QuestGoToZ` otomatik bulunur)*.
3. **İndir ve Kur / Güncelle** butonuna bas.
4. Oyunu aç (veya güncelleme sonrası `/reload` yaz).

### Manuel Kurulum
1. [**Releases**](https://github.com/FRKN74/QuestGoToZ/releases/latest) sayfasından `QuestGoToZ-v*.zip` dosyasını indir.
2. ZIP içindeki `QuestGoToZ` klasörünü `World of Warcraft\_forever_\Interface\AddOns\` dizinine çıkart.

---

## Özellikler

- **Karakter Altı 3D Yön Oku & Minimap Yeşil Çizgisi:** Hedefe `<= 30 m` kala parlayan varış ikonu; mesafeler metre (`m` / `km`) cinsinden.
- **Bölge Bazlı & Katlanabilir Görev Listesi:** Tamamlanan, Alınan, Alınmayan görevler; solunda sağa bakan mini yönlendirme oku, köşeden sürükleyerek serbest boyutlandırma ve üstte **Level / XP + Meslekler** barı.
- **Birlikte Yapılabilecek Görevler:** Yakın merkezli görevleri otomatik gruplar.
- **Sıradaki En İyi Görev (`Siradaki` Butonu):** Yakınlık, küme boyutu, XP ve tamamlanma oranına göre en iyi görevi puanlayıp yönlendirir.
- **Görev Mobu İşaretleri & Envanter Vurgusu:** Nameplate kenarında eşya düşen görevlerde **el**, öldürme görevlerinde **kılıç** ikonu + kalan sayı; mouseover tooltip satırı; çantada görev eşyalarına **turuncu kenarlık**.
- **Dünya Haritası (`M`) Yeşil Daireler:** Tamamlanmış görevler haritada yeşil daire ile görünür.
- **Ceset Yönü:** Ölünce ceset konumuna otomatik waypoint koyar, canlanınca temizler.
- **Günlük Rahatlıklar:** En yakın Class Trainer (limit 1), en yakın hizmetler (Satıcı/Posta/Han/Uçuş), çanta `%90` doluluk satıcı uyarısı, görev günlüğü doluluk uyarısı + `[Birakilabilir]` etiketi, en değerli ödüle altın simgesi, `[Elite]`/`[Grup]` rozeti, sürüklenebilir **Görev Eşyası Kullan** butonu.
- **Profiller & Sessiz Mod:** `/qgt` ayar penceresinde çoklu profil ve tüm sesleri kapatan sessiz mod.

---

## Oyun İçi Komutlar

- `/qgt` — Ayar penceresini aç/kapa
- `/qgt siradaki` — En yüksek puanlı göreve yönlendir
- `/qgt lock` — Çerçeveleri kilitle / aç
- `/qgt clear` — Aktif waypoint'i temizle
- `/qgt sessiz` — Sessiz modu aç/kapa
