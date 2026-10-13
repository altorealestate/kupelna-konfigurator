# Konfigurátor kúpeľne

Demo konfigurátora kúpeľne. Klient si vyberá obklad, dlažbu, batérie, umývadlo a sprchový žľab a vizualizácia sa okamžite mení.

**Živé demo:** https://altorealestate.github.io/kupelna-konfigurator/

## Ako to funguje

- Každý produkt z katalógu sa do pôvodnej vizualizácie (štandard ST1) vložil jednou generáciou cez [kie.ai](https://kie.ai), model `gpt-image-2-5-flare-image-to-image` v rozlíšení 1K. Jedna generácia stojí 6 kreditov (≈ $0,03) a trvá asi 75 s.
- Kombinácie sa negenerujú. Z každej generácie sa vyreže len zmenená oblasť a stránka ju poskladá nad zvolený obklad. Z 10 generácií je tak 216 kombinácií.
- Batérie a umývadlo majú vrstvu pre každý obklad zvlášť, aby okolo nich na tmavom obklade nebola svetlá aura z pôvodnej steny.
- Ide o orientačný náhľad. Finálnu vizualizáciu zostavy, ktorú si klient vyberie, je lepšie vygenerovať naraz.

## Štruktúra

| Súbor | Účel |
|---|---|
| `demo/index.html` | Stránka konfigurátora (funguje aj otvorená priamo zo súboru) |
| `demo/img/` | Podklady, vrstvy a náhľady (vytvára `zostav.ps1`) |
| `demo/varianty.json` | Kategórie, produkty, prompty a oblasti vrstiev |
| `demo/vysledky.json` | Ktorý výstup patrí ku ktorému variantu |
| `demo/generuj.ps1` | Paralelné generovanie variantov (stojí kredity) |
| `demo/zostav.ps1`, `demo/obrazky.cs` | Skladanie vrstiev a dát do stránky (zadarmo) |
| `kie-image.ps1` | Volanie kie.ai (upload, úloha, stiahnutie výsledku) |

## Pridanie produktu

1. Do `demo/varianty.json` pridať variant: kategóriu, názov, cestu k fotke produktu a prompt.
2. `& .\demo\generuj.ps1` vygeneruje variant (6 kreditov).
3. `& .\demo\zostav.ps1` prepočíta vrstvy a dáta v `demo/index.html`.
4. Commit a push. GitHub Pages sa aktualizuje do minúty.

## Čo nie je v repozitári

Katalóg produktových fotiek (`configurator-images-SPT`), pôvodné rendery (`Podkladove-obrazky`) a surové výstupy z kie.ai (`vystupy`) sú len lokálne. Bez nich `generuj.ps1` a `zostav.ps1` nefungujú, samotná stránka áno. API kľúč je v premennej prostredia `KIE_API_KEY`, nikdy nie v súboroch.
