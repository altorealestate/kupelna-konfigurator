# Konfigurátor kúpeľne

Demo konfigurátora kúpeľne. Klient si vyberá obklad, dlažbu, batérie, umývadlo a sprchový žľab a vizualizácia sa okamžite mení.

**Živé demo:** https://altorealestate.github.io/kupelna-konfigurator/

## Ako to funguje

- Každý produkt z katalógu sa do pôvodnej vizualizácie (štandard ST1) vložil generáciou. Batérie, umývadlá, dlažba Timeless Amani a žľab vznikli cez [kie.ai](https://kie.ai), model `gpt-image-2-5-flare-image-to-image` v rozlíšení 4K (3312 × 2480 px, 16 kreditov ≈ $0,08 za generáciu). Obklady, všetko, čo sa na nich generuje, a dlažba Stone Life Graphite idú od 15. 10. 2026 priamo cez OpenAI API (`gpt-image-2.5-sunburst`, kvalita high) v 2K (≈ $0,08–0,09 za generáciu, asi 40 s). V 4K model kreslil kameň ako zrnitý reliéf, preto prompt obkladu aj dlažby výslovne žiada rovnú hladkú platňu.
- Kombinácie sa negenerujú. Z každej generácie sa vyreže len zmenená oblasť a stránka ju poskladá nad zvolený obklad. Z 37 generácií je tak 216 kombinácií.
- Model scénu mierne preráma (zväčší alebo posunie o pár pixelov), preto sa každý výsledok pred skladaním automaticky zarovná na podklad; výsledok v 2K sa pritom roztiahne na rámec stránky.
- Batérie a umývadlá majú na každom obklade rovnakú veľkosť a polohu: vygenerujú sa raz, tie isté pixely sa vložia na každý obklad a AI len dočistí okolie (zvyšky pôvodných batérií, svetlé okraje). Bronzové batérie sú prefarbené čierne, takže ani zmena farby neposunie tvar. K batériám patrí aj sifón pod umývadlom a krytka prepadu vane, majú rovnakú farbu ako batérie. Umývadlová batéria smeruje výtokom k divákovi ako pôvodná a má jej veľkosť (model ju nakreslil väčšiu, zmenší sa pri skladaní).
- Sprchový žľab má vlastnú vrstvu len s kovom (aj pôvodný), dlažba je pod ním celá, takže pri každej dlažbe je pás pri stene nový.
- Doplnky na polici (váza s vetvičkou, difuzér, mydlo, podnos) sú na každom obklade pôvodné: generácia obkladu ich prekreslí a zdeformuje, preto ich AI z obkladu len odstráni a vložia sa tie z pôvodnej vizualizácie.
- Sprcha v ST1 je Hansgrohe Pulsify S 260 v chróme, čierna a bronzová sa preto iba prefarbí. Umývadlá majú v prompte rozmer voči pôvodnému Laufen living SQ 600 × 340 mm.
- Ide o orientačný náhľad. Finálnu vizualizáciu zostavy, ktorú si klient vyberie, je lepšie vygenerovať naraz.

## Nový postup: produkty nezávislé od obkladu

**Porovnanie:** https://altorealestate.github.io/kupelna-konfigurator/demo2/ (prepínač Nový postup / Doterajší pri tej istej zostave)

Pri celom katalógu (desiatky obkladov) by doterajší postup potreboval 7 generácií na každý obklad. V novom postupe:

- AI raz odstráni z vizualizácie batérie, umývadlo, sifón a doplnky (prázdna scéna) a každý obklad sa generuje raz na nej, aj s odrazom v zrkadle. Na obklad teda 1 generácia (2K, ≈ $0,09).
- Každý produkt sa z vlastnej generácie vyreže raz, aj s tieňom, a tá istá vrstva sa použije na všetkých obkladoch. Obrys dáva zelený kľúč (AI natrie produkt na zeleno), farba okrajov sa očistí od steny, na ktorej vznikol. Na produkt 1 generácia + kľúč, nezávisle od počtu obkladov.
- Pilot na ST1: 7 generácií za $0,85, 22 súborov, 4,4 MB (doterajšie demo 76 súborov).

## Štruktúra

| Súbor | Účel |
|---|---|
| `demo/index.html` | Stránka konfigurátora (funguje aj otvorená priamo zo súboru) |
| `demo/img/` | Podklady, vrstvy a náhľady (vytvára `zostav.ps1`) |
| `demo/varianty.json` | Kategórie, produkty, prompty a oblasti vrstiev |
| `demo/vysledky.json` | Ktorý výstup patrí ku ktorému variantu |
| `demo/generuj.ps1` | Paralelné generovanie variantov po fázach podľa závislostí (stojí peniaze; `-Plan` len vypíše úlohy a cenu) |
| `demo/zostav.ps1`, `demo/obrazky.cs` | Zarovnanie, skladanie vrstiev a dát do stránky (zadarmo) |
| `demo/spolocne.ps1` | Spoločné funkcie oboch skriptov (zarovnanie, masky) |
| `demo/kontrola.py` | Kontrolné hárky generácií a zostavy, screenshoty stránky, kontrola obrázkov (zadarmo) |
| `demo2/index.html`, `demo2/img/` | Stránka nového postupu s prepínačom na doterajší (dlažbu, žľab a náhľady berie z `demo/`) |
| `demo/zostav2.ps1` | Vrstvy nového postupu a dáta do `demo2/index.html` (spúšťať po `zostav.ps1`) |
| `openai-image.ps1` | Volanie OpenAI Images API (úprava obrázka, uloženie výsledku a jeho ceny) |
| `kie-image.ps1` | Staršie volanie kie.ai (upload, úloha, stiahnutie výsledku) |

## Pridanie produktu

1. Do `demo/varianty.json` pridať variant: kategóriu, názov, cestu k fotke produktu a prompt.
2. `& .\demo\generuj.ps1` vygeneruje variant (cenu vopred odhadne `-Plan`, skutočná je v `.json` každého výsledku; batérie a umývadlá ešte raz na každý obklad, umývadlo aj zelenú masku, teda 4–5 obrázkov).
3. `& .\demo\zostav.ps1` prepočíta vrstvy a dáta v `demo/index.html`.
4. Commit a push. GitHub Pages sa aktualizuje do minúty.

## Čo nie je v repozitári

Katalóg produktových fotiek (`configurator-images-SPT`), pôvodné rendery (`Podkladove-obrazky`) a surové výstupy generovania (`vystupy`) sú len lokálne. Bez nich `generuj.ps1` a `zostav.ps1` nefungujú, samotná stránka áno. API kľúče (`OPENAI_API_KEY`, `KIE_API_KEY`) sú v premenných prostredia alebo v lokálnom `.env`, nikdy nie v repozitári.
