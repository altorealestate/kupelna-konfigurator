# Konfigurátor kúpeľne

Demo konfigurátora kúpeľne. Klient si vyberá obklad, dlažbu, batérie, umývadlo a sprchový žľab a vizualizácia sa okamžite mení.

**Živé demo:** https://altorealestate.github.io/kupelna-konfigurator/

## Ako to funguje

- Každý produkt z katalógu sa do pôvodnej vizualizácie (štandard ST1) vložil generáciou cez [kie.ai](https://kie.ai), model `gpt-image-2-5-flare-image-to-image` v rozlíšení 4K (3312 × 2480 px). Jedna generácia stojí 16 kreditov (≈ $0,08) a trvá asi 1–2 min.
- Kombinácie sa negenerujú. Z každej generácie sa vyreže len zmenená oblasť a stránka ju poskladá nad zvolený obklad. Z 25 generácií je tak 216 kombinácií.
- Model v 4K scénu mierne preráma (zväčší alebo posunie o pár pixelov), preto sa každý výsledok pred skladaním automaticky zarovná na podklad.
- Batérie a umývadlá majú na každom obklade rovnakú veľkosť a polohu: vygenerujú sa raz, tie isté pixely sa vložia na každý obklad a AI len dočistí okolie (zvyšky pôvodných batérií, svetlé okraje). Bronzové batérie sú prefarbené čierne, takže ani zmena farby neposunie tvar.
- Sprcha v ST1 je Hansgrohe Pulsify S 260 v chróme, čierna a bronzová sa preto iba prefarbí. Umývadlá majú v prompte rozmer voči pôvodnému Laufen living SQ 600 × 340 mm.
- Ide o orientačný náhľad. Finálnu vizualizáciu zostavy, ktorú si klient vyberie, je lepšie vygenerovať naraz.

## Štruktúra

| Súbor | Účel |
|---|---|
| `demo/index.html` | Stránka konfigurátora (funguje aj otvorená priamo zo súboru) |
| `demo/img/` | Podklady, vrstvy a náhľady (vytvára `zostav.ps1`) |
| `demo/varianty.json` | Kategórie, produkty, prompty a oblasti vrstiev |
| `demo/vysledky.json` | Ktorý výstup patrí ku ktorému variantu |
| `demo/generuj.ps1` | Paralelné generovanie variantov po fázach podľa závislostí (stojí kredity) |
| `demo/zostav.ps1`, `demo/obrazky.cs` | Zarovnanie, skladanie vrstiev a dát do stránky (zadarmo) |
| `demo/spolocne.ps1` | Spoločné funkcie oboch skriptov (zarovnanie, masky) |
| `kie-image.ps1` | Volanie kie.ai (upload, úloha, stiahnutie výsledku) |

## Pridanie produktu

1. Do `demo/varianty.json` pridať variant: kategóriu, názov, cestu k fotke produktu a prompt.
2. `& .\demo\generuj.ps1` vygeneruje variant (16 kreditov za obrázok; batérie a umývadlá ešte raz na každý obklad, umývadlo aj zelenú masku, teda 4–5 obrázkov).
3. `& .\demo\zostav.ps1` prepočíta vrstvy a dáta v `demo/index.html`.
4. Commit a push. GitHub Pages sa aktualizuje do minúty.

## Čo nie je v repozitári

Katalóg produktových fotiek (`configurator-images-SPT`), pôvodné rendery (`Podkladove-obrazky`) a surové výstupy z kie.ai (`vystupy`) sú len lokálne. Bez nich `generuj.ps1` a `zostav.ps1` nefungujú, samotná stránka áno. API kľúč je v premennej prostredia `KIE_API_KEY`, nikdy nie v súboroch.
