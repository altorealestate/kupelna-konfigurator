# Vizualizácia kúpeľne

Vizualizácie kúpeľní (výmena obkladu, batérií, umývadiel…) cez kie.ai model `gpt-image-2-5-flare-image-to-image`.

## Generovanie obrázkov – `kie-image.ps1`

```powershell
& .\kie-image.ps1 -Prompt "Keep everything unchanged, replace only the wall tiles with the tile from the second image." `
    -Images '.\foto-kupelne.jpg', '.\obklad.jpg' -Resolution 2K
```

- `-Images`: lokálne cesty aj http(s) URL; prvý obrázok = fotka na úpravu, ďalšie = referencie produktov. Lokálne súbory sa automaticky uploadnú na kie.ai (jpg/png/webp, max 30 MB).
- `-AspectRatio` (default `auto`), `-Resolution` `1K|2K|4K` (default `1K`; pomery 27:16, 16:27, 9:8, 8:9 len 1K), `-Background`, `-PromptFile` pre dlhé prompty, `-Model` pre iný kie.ai model.
- Výstup: `vystupy\yyyyMMdd-HHmmss_<taskId>_<n>.<ext>` + `.json` s parametrami tasku. Skript vypíše cesty k stiahnutým obrázkom.
- Po timeoute (default 600 s) netreba generovať znova: `& .\kie-image.ps1 -TaskId <taskId>`.
- Mimo PowerShell tool session: `powershell -ExecutionPolicy Bypass -File .\kie-image.ps1 ... -Images "a.jpg|b.jpg"` (viac obrázkov oddeliť `|`).

## Demo konfigurátora – `demo\`

- `varianty.json`: kategórie (typ `podklad` = obklad ako celý obrázok, `plocha`/`objekt` = vrstva v oblasti `roi`) a varianty (prompt + referenčné fotky). Podklad: `demo\zdroje\KUPELNA_ST1_2048.jpg`, 4:3, 1K.
- `& .\demo\generuj.ps1` vygeneruje paralelne varianty, ktoré ešte nemajú výsledok (`-Ids x,y`, `-Force`), a zapíše ich do `vysledky.json`.
- `& .\demo\zostav.ps1` (bez kreditov) z výsledkov vyrobí `demo\img\` (podklady, PNG vrstvy, náhľady) a vloží dáta do `index.html` medzi `/*DATA*/ … /*/DATA*/`. `-Ladenie <priečinok>` uloží masky a testovacie kombinácie.
- Kombinácie sa skladajú z vrstiev: GPT 2.5 drží scénu takmer na pixel. Obklad, dlažba a žľab = 1 generácia na produkt. Batérie a umývadlo (`naObkladoch`) sa generujú aj priamo na každom obklade (`<variant>@<obklad>` vo `vysledky.json`), inak by na tmavom obklade ostali svetlé škvrny a zvyšky pôvodných batérií. Vrstva vždy pokrýva aj obrys pôvodného objektu; `stlpec` pri umývadle vyreže batériu nad okrajom misy (misa je navrchu, batéria za ňou).
- Prompt batérií vymenúva každý produkt a jeho časti (výtok vaňovej batérie, posuvný držiak, hadica) – bez toho ich model občas vynechá.
- `index.html` funguje otvorený priamo zo súboru (bez servera).
- GitHub: verejný repo `altorealestate/kupelna-konfigurator`, GitHub Pages z `main` (koreňový `index.html` presmeruje na `demo/`): https://altorealestate.github.io/kupelna-konfigurator/ – všetko commitnuté je verejné. Katalóg, `Podkladove-obrazky` a `vystupy` sú v `.gitignore`.

## Dôležité

- API kľúč je v User environment variable `KIE_API_KEY` (nie v súboroch projektu – priečinok sa synchronizuje cez OneDrive).
- Každá generácia stojí kredity na kie.ai – negenerovať zbytočne a neopakovať pri chybe bez dôvodu.
- Uploadnuté vstupy sa na kie.ai mažú po 24 h, URL výsledkov sú dočasné – preto sa výsledky hneď sťahujú.
- Prompty písať po anglicky; explicitne vymenovať, čo má ostať nezmenené (kamera, svetlo, ostatné prvky).
- Produktové fotky (Florim obklady, Hansgrohe/Axor batérie, Laufen umývadlá, dvere, kľučky…) sú rozbalené v `configurator-images-SPT\<kategória>\<produktová rada>\<variant>.jpg|webp` (zdroj: `configurator-images-SPT.zip`). Príliš dlhé názvy priečinkov (limit cesty 260 znakov, dlhé cesty v systéme nie sú zapnuté) sú skrátené; pôvodné plné názvy sú v `configurator-images-SPT\_povodne-nazvy-priecinkov.txt`. Pri opätovnom rozbaľovaní: UTF-8-aware (.NET `ZipFile`), nie `unzip` v Git Bash.
- Druhý katalóg `configurator-images-FLR\` (zo `configurator-images-FLR.zip`) má rovnakú štruktúru, ale iné názvy kategórií (napr. `Obklad`, `Batérie - sprchové`, `Sanita - WC Misa + sedátko`) a čiastočne iné produkty; skrátené priečinky sú v `configurator-images-FLR\_povodne-nazvy-priecinkov.txt`.
