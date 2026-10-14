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
- `-Model` vie aj `nano-banana-2-1` / `nano-banana-pro` (vstup `image_input`, 1K/2K/4K) a `grok-imagine-image-2-0/image-edit` (vstup `image_urls`, bez rozlíšenia, ~1600 px). Test 2026-10-13 (`vystupy\test-modely\porovnanie`): GPT 2.5 najvernejšie produkty; NanoBanana 2.1 4K drží scénu presne, ale posúva farbu obkladu do oranžova a nekopíruje tvar batérie; Grok pridáva nevyžiadané prvky. GPT 2.5 v 4K (3312×2480) mierne preráma scénu (~0,5–1 % zoom, pár px posun), pre vrstvy treba zarovnanie.

## Demo konfigurátora – `demo\`

- `varianty.json`: kategórie (typ `podklad` = obklad ako celý obrázok, `plocha`/`objekt` = vrstva v oblasti `roi`), varianty (prompt + referenčné fotky) a `pomocne` generácie. Podklad: `demo\zdroje\KUPELNA_ST1_4096.jpg`, 4:3, 4K; spoločný rámec `sirka`×`vyska` = 3312×2484.
- `& .\demo\generuj.ps1` vygeneruje paralelne, po fázach podľa závislostí, všetko, čo ešte nemá výsledok (`-Ids` s wildcardmi, napr. `baterie-black*`; `-Force`), a zapíše do `vysledky.json` aj `vstup` a `zarovnanie`.
- `& .\demo\zostav.ps1` (bez kreditov) z výsledkov vyrobí `demo\img\` (podklady, PNG vrstvy, náhľady) a vloží dáta do `index.html` medzi `/*DATA*/ … /*/DATA*/`. `-Ladenie <priečinok>` uloží masky a testovacie kombinácie (skladané z hotových PNG ako stránka). `spolocne.ps1` = spoločné funkcie (zarovnanie, masky).
- Zarovnanie: GPT 2.5 v 4K scénu preráma (zoom 0,5–2,5 %, posun až ~40 px), `Zarovnanie.Najdi` nájde mierku a posun voči vstupu úlohy; `Get-Aligned` s kategóriou doladí aj lokálny posun v každom obdĺžniku `roi`.
- Batérie a umývadlo (`naObkladoch`): variant sa vygeneruje raz na pôvodnom obklade, jeho prvok sa vyreže a tie isté pixely sa vložia na každý obklad; AI podľa `promptNaObklad` len dočistí okolie (`<variant>@<obklad>`), `zostav` potom jadro prvku obnoví z pôvodnej generácie → rovnaká veľkosť a poloha na všetkých obkladoch. Pôvodné batérie sa pred vložením hrubo zamažú (maska z `prazdne-baterie`), inak ostanú priesvitné zvyšky. Prvok sa vyreže rozdielom voči `prazdny`; biele umývadlo na svetlej stene sa farbou oddeliť nedá, preto ho AI natrie na zeleno (`promptKluc`, `<variant>#kluc`). Okrajové pixely prvku sa pred vložením prefarbia z pozadia pôvodného obkladu na pozadie nového (`Prefarbi`; pri batériách pixel po pixeli podľa `prazdne-baterie`), inak AI okolo bronzu nechá svetlú auru. Okraj misy pre `stlpec` sa hľadá v maske prvku, nie v rozdiele (ten zachytí aj prekreslenú stenu).
- Obklad nesmie meniť policu – Graphit raz „zapustil“ umývadlo do police a na ostatných umývadlách potom ostal obdĺžnikový obrys; prompt obkladov to teraz výslovne zakazuje. Pri problémoch s jedným obkladom stačí `-Ids obklad-x,*@obklad-x -Force`.
- Bronzové batérie sú prefarbené čierne (`zVariantu`). Sprcha v ST1 je Pulsify S 260 chróm → čierna/bronz sa iba prefarbí. K batériám patrí aj sifón pod policou a krytka prepadu vane (vlastné obdĺžniky v `roi`), v katalógu nie sú, farba sa len zjednocuje s batériami: `baterie-black` = prefarbenie sifónu a prepadu na pomocnom `baterie-black-zaklad` (pôvodná generácia čiernych batérií, `pomocne` môžu mať `referencie`). Umývadlá majú v prompte rozmer voči pôvodnému Laufen living SQ 600×340 mm (bez toho majú všetky rovnakú šírku ako pôvodné).
- Dlažba: model v 4K občas prekreslí žľab → `bezObjektov: ["zlab"]` ho z vrstiev dlažby vyreže. `stlpec` pri umývadle vyreže batériu nad okrajom misy (misa je navrchu, batéria za ňou).
- `index.html` funguje otvorený priamo zo súboru (bez servera); obrázky sa načítajú až pri zobrazení, zvyšok sa prednačíta.
- PowerShell: premenné nerozlišujú veľkosť písmen (`$base` prepíše parameter `[string]$Base`!); `Add-Type` nevie v tej istej session preložiť zmenený `obrazky.cs` → skripty spúšťať v novom procese (`powershell -NoProfile -ExecutionPolicy Bypass -File …`).
- GitHub: verejný repo `altorealestate/kupelna-konfigurator`, GitHub Pages z `main` (koreňový `index.html` presmeruje na `demo/`): https://altorealestate.github.io/kupelna-konfigurator/ – všetko commitnuté je verejné. Katalóg, `Podkladove-obrazky` a `vystupy` sú v `.gitignore`.

## Dôležité

- API kľúč je v User environment variable `KIE_API_KEY` (nie v súboroch projektu – priečinok sa synchronizuje cez OneDrive).
- Každá generácia stojí kredity na kie.ai – negenerovať zbytočne a neopakovať pri chybe bez dôvodu.
- Uploadnuté vstupy sa na kie.ai mažú po 24 h, URL výsledkov sú dočasné – preto sa výsledky hneď sťahujú.
- Prompty písať po anglicky; explicitne vymenovať, čo má ostať nezmenené (kamera, svetlo, ostatné prvky).
- Produktové fotky (Florim obklady, Hansgrohe/Axor batérie, Laufen umývadlá, dvere, kľučky…) sú rozbalené v `configurator-images-SPT\<kategória>\<produktová rada>\<variant>.jpg|webp` (zdroj: `configurator-images-SPT.zip`). Príliš dlhé názvy priečinkov (limit cesty 260 znakov, dlhé cesty v systéme nie sú zapnuté) sú skrátené; pôvodné plné názvy sú v `configurator-images-SPT\_povodne-nazvy-priecinkov.txt`. Pri opätovnom rozbaľovaní: UTF-8-aware (.NET `ZipFile`), nie `unzip` v Git Bash.
- Druhý katalóg `configurator-images-FLR\` (zo `configurator-images-FLR.zip`) má rovnakú štruktúru, ale iné názvy kategórií (napr. `Obklad`, `Batérie - sprchové`, `Sanita - WC Misa + sedátko`) a čiastočne iné produkty; skrátené priečinky sú v `configurator-images-FLR\_povodne-nazvy-priecinkov.txt`.
