# Konfigurátor kúpeľne

Demo konfigurátora kúpeľne. Klient si vyberá obklad, dlažbu, batérie, umývadlo a sprchový žľab a vizualizácia sa okamžite mení.

**Živé demo:** https://altorealestate.github.io/kupelna-konfigurator/

## Ako to funguje

- Každý produkt z katalógu sa do pôvodnej vizualizácie (štandard ST1) vložil generáciou. Batérie, umývadlá, dlažba a žľab vznikli cez [kie.ai](https://kie.ai), model `gpt-image-2-5-flare-image-to-image` v rozlíšení 4K (3312 × 2480 px, 16 kreditov ≈ $0,08 za generáciu). Obklady a všetko, čo sa na nich generuje, idú od 15. 10. 2026 priamo cez OpenAI API (`gpt-image-2.5-sunburst`, kvalita high) v 2K (≈ $0,08–0,09 za generáciu, asi 40 s). V 4K model kreslil kameň ako zrnitý reliéf, preto prompt obkladu výslovne žiada rovnú hladkú platňu.
- Kombinácie sa negenerujú. Z každej generácie sa vyreže len zmenená oblasť a stránka ju poskladá nad zvolený obklad. Z 37 generácií je tak 216 kombinácií.
- Model scénu mierne preráma (zväčší alebo posunie o pár pixelov), preto sa každý výsledok pred skladaním automaticky zarovná na podklad; výsledok v 2K sa pritom roztiahne na rámec stránky.
- Batérie a umývadlá majú na každom obklade rovnakú veľkosť a polohu: vygenerujú sa raz, tie isté pixely sa vložia na každý obklad a AI len dočistí okolie (zvyšky pôvodných batérií, svetlé okraje). Bronzové batérie sú prefarbené čierne, takže ani zmena farby neposunie tvar. K batériám patrí aj sifón pod umývadlom a krytka prepadu vane, majú rovnakú farbu ako batérie. Umývadlová batéria smeruje výtokom k divákovi ako pôvodná a má jej veľkosť (model ju nakreslil väčšiu, zmenší sa pri skladaní).
- Sprchový žľab má vlastnú vrstvu len s kovom (aj pôvodný), dlažba je pod ním celá, takže pri každej dlažbe je pás pri stene nový.
- Doplnky na polici (váza s vetvičkou, difuzér, mydlo, podnos) sú na každom obklade pôvodné: generácia obkladu ich prekreslí a zdeformuje, preto ich AI z obkladu len odstráni a vložia sa tie z pôvodnej vizualizácie.
- Sprcha v ST1 je Hansgrohe Pulsify S 260 v chróme, čierna a bronzová sa preto iba prefarbí. Umývadlá majú v prompte rozmer voči pôvodnému Laufen living SQ 600 × 340 mm.
- Ide o orientačný náhľad. Finálnu vizualizáciu zostavy, ktorú si klient vyberie, je lepšie vygenerovať naraz.

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
| `openai-image.ps1` | Volanie OpenAI Images API (úprava obrázka, uloženie výsledku a jeho ceny) |
| `kie-image.ps1` | Staršie volanie kie.ai (upload, úloha, stiahnutie výsledku) |

## Pridanie produktu

1. Do `demo/varianty.json` pridať variant: kategóriu, názov, cestu k fotke produktu a prompt.
2. `& .\demo\generuj.ps1` vygeneruje variant (cenu vopred odhadne `-Plan`, skutočná je v `.json` každého výsledku; batérie a umývadlá ešte raz na každý obklad, umývadlo aj zelenú masku, teda 4–5 obrázkov).
3. `& .\demo\zostav.ps1` prepočíta vrstvy a dáta v `demo/index.html`.
4. Commit a push. GitHub Pages sa aktualizuje do minúty.

## Čo nie je v repozitári

Katalóg produktových fotiek (`configurator-images-SPT`), pôvodné rendery (`Podkladove-obrazky`) a surové výstupy generovania (`vystupy`) sú len lokálne. Bez nich `generuj.ps1` a `zostav.ps1` nefungujú, samotná stránka áno. API kľúče (`OPENAI_API_KEY`, `KIE_API_KEY`) sú v premenných prostredia alebo v lokálnom `.env`, nikdy nie v repozitári.
