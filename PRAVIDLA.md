# Pravidlá a pasce – konfigurátor kúpeľne

Kontrolný zoznam ku každej zmene dema a zoznam chýb, ktoré sa už stali. Ako jednotlivé mechanizmy fungujú, opisuje CLAUDE.md; tu je, na čo si treba dať pozor.

## 1. Pred generovaním

- **Cena a súhlas.** Každá generácia stojí peniaze. OpenAI účtuje tokeny, takže cena závisí od rozlíšenia, kvality a počtu vstupných obrázkov a skutočná suma je v `.json` výsledku (`costUsd`). Staršie kie.ai stálo 16 kreditov ≈ $0,08 za 4K. Pred sériou spočítať úlohy a generovať až so súhlasom. Pri chybe neopakovať naslepo, najprv zistiť príčinu. OpenAI požiadavku po timeoute nemožno obnoviť, ale zaplatí sa.
  - `generuj.ps1 … -Plan` vypíše fázy, úlohy, cenu a zostatok; ten výpis ukázať pri žiadosti o súhlas.
  - Hook `kredity.sh` si spustenie `generuj.ps1`/`openai-image.ps1`/`kie-image.ps1` vyžiada potvrdiť. Neobchádzať ho (napr. iným volaním skriptu).
  - Nový obklad: obklad + `prazdne-doplnky@` + 2× umývadlo@ + čierne@ + bronzové@ + `zrkadlo@` = 7 generácií, všetky v 2K (asi $0,08–0,09 za kus).
  - Nová batéria (čierna + bronz): aspoň variant + bronz + 3× čierna@ + 3× bronz@ = 8 generácií, plus prípadné pomocné kroky (prefarbenie sifónu, otočenie).
  - Nové umývadlo: variant + `#kluc` + 3× @obklad = 5 generácií.
- **Model:** OpenAI `gpt-image-2.5-sunburst` (`openai-image.ps1`, od 14. 10. 2026), demo v 4K, obklady a všetko na nich (`*@obklad-…`) aj dlažba v 2K (`resolution` kategórie), rýchle testy v 1K. Iný model len na výslovnú požiadavku. Všetky doterajšie výsledky dema sú z kie.ai `gpt-image-2-5-flare`: nová generácia z OpenAI sa môže líšiť farbou, ostrosťou aj prerámovaním, preto pri prvej sérii skontrolovať aj zhodu s výsledkami z kie (krok 3, `kontrola.py zostava`).
- **Model vždy prekreslí celý obrázok, nielen to, čo meníme.** Generácia obkladu prekreslí aj doplnky na polici, policu, umývadlo, batérie a žľab; generácia dlažby prekreslí žľab. Pre každú vec, ktorá sa meniť nemá a stránka ju berie z danej generácie, musí existovať poistka (vrátenie z podkladu, vyrezanie z vrstvy) alebo aspoň kontrola v kroku 2.
- **Prompt:**
  - po anglicky;
  - obklad: veta o rovnej hladkej platni s vytlačeným vzorom, bez reliéfu, zŕn a šumu (skopírovať z existujúceho obkladu vo `varianty.json`; pri leštenom obklade bez „matte“);
  - dlažba: to isté pre dlaždicu 600 × 600 a slovami aj tón a farbu produktu (Stone Life Graphite: tmavá antracitová, tmavšia ako steny, bez zeleného či olivového nádychu), inak ju model zosvetlí;
  - vymenovať všetky časti produktu (výtok vane, ručná sprcha, hadica, držiak…), inak ich model vynechá;
  - rozmer voči pôvodnému produktu (umývadlo Laufen living SQ 600×340 mm), inak model zachová pôvodnú šírku;
  - vymenovať, čo ostáva: kamera, svetlo, polica s presným tvarom a hrúbkou, umývadlo stojí na polici (nie zapustené), batérie, sifón, žľab, sklenená zástena, zrkadlo, vaňa, stolička, doplnky na polici, strop;
  - pri prefarbení presne opísať, čo ostáva na mieste (rozeta sifónu vycentrovaná za rúrkou, žiadny chrómový okraj ani druhý obrys).
- **Orientácia produktu:** umývadlová batéria smeruje výtokom k divákovi ako pôvodná. Produktová fotka ju vie otočiť bokom.
- **Najprv jedna testovacia generácia** a jej kontrola (krok 2), až potom celá séria.
- **Závislosti:** nový obklad X znamená aj `*@obklad-x` (vrátane `prazdne-doplnky@obklad-x`), takže stačí `-Ids obklad-x,*@obklad-x -Force`. Nová čierna batéria znamená aj bronzovú a všetky ich `@obklad`.
- **`prazdne-baterie` nepregenerovávať.** Pokus odstrániť aj sifón a prepad zlyhal: model nechal batériu aj sifón a zmazal len prepad.

## 2. Kontrola po každej generácii

Porovnať výsledok s pôvodnou vizualizáciou vo výrezoch 1:1, nie v celom obrázku: `python demo\kontrola.py generacia --posledne N` (alebo id, wildcardy) urobí hárky vstup | výsledok | rozdiel pre všetky oblasti zoznamu nižšie. `!` = zmena mimo oblasti úlohy. Čísla sú len vodítko, pri obklade sa mení celá stena, takže rozhoduje pohľad na hárky. Kontroluje sa nielen to, čo sa menilo, ale celý tento zoznam:

- [ ] menený prvok: vzor a farba obkladu podľa referencie, tvar produktu, všetky jeho časti, správny rozmer
- [ ] povrch obkladu pri veľkosti ako na stránke (~925 px a 1850 px): hladká platňa, nie reliéf ani zrnká
- [ ] **doplnky na polici:** váza s vetvičkou, difuzér s tyčinkami, dávkovač mydla, podnos so zrolovaným uterákom. Tvar ani počet sa nesmie zmeniť (nesmie pribudnúť fľaša ani podnos).
- [ ] polica (hrúbka, hrany, tieň) a umývadlo na nej, nie zapustené
- [ ] batérie, sifón, krytka prepadu vane, sklenená zástena s chrómovou vzperou
- [ ] žľab a pás podlahy medzi ním a stenou (pri novej dlažbe musí byť nový), vaňa, stolička, strop a bodovky
- [ ] zrkadlo a jeho svetlo; v odraze má protiľahlá stena okolo dverí nový obklad
- [ ] veľkosť batérie voči pôvodnej (výška tela aj výtoku)
- [ ] na tmavom obklade (Graphit): svetlé aury, škvrny, duchovia starých chrómových prvkov
- [ ] `zhoda` zarovnania vo výpise `generuj.ps1`. Nízka zhoda znamená, že model scénu posunul viac než obvykle.

## 3. Kontrola po zostavení

- `zostav.ps1 -Ladenie <priečinok>` (v scratchpade): prejsť masky aj `kombinacia-*.jpg`.
- `python demo\kontrola.py zostava` (alebo `-k baterie umyvadlo`): každý variant na všetkých štyroch obkladoch (pôvodný, Calacatta, Graphit, Travertine) v zväčšených výrezoch, poskladaný ako stránka. `-k obklad` ukáže oblasti kontrolného zoznamu (doplnky, pás za žľabom, zrkadlo…) na každom obklade, `--vyber dlazba=…` pridá inú dlažbu.
- Prepínať obklady pri tej istej batérii a umývadle: veľkosť a poloha sa nesmú zmeniť. Rovnako čierna a bronzová batéria.
- Umývadlová batéria je v celom výreze kategórie malá: `kontrola.py zostava -k baterie --oblast bateria-umyvadlo` (zväčšený výrez). Celá batéria vrátane páky musí mať na každom obklade rovnaký tvar a farbu, bez svetlého obrysu.
- Každé umývadlo celé až po konce (široké Savoy zasahuje k doplnkom).
- Výpis `object changed by …` (ako veľmi AI zmenila vložený prvok) a varovania `has no result` / `Layer … is empty`.
- `python demo\kontrola.py stranka`: screenshoty v 1440 a 390 px, rozbité obrázky, chyby v konzole, chýbajúce súbory. Pozrieť aj mobil.

## 4. Zverejnenie

- README: počet generácií a kombinácií.
- Nová pasca patrí do tohto súboru; nový mechanizmus do CLAUDE.md.
- Commit a push sú verejné (GitHub Pages). Katalóg, `Podkladove-obrazky` a `vystupy` sú v `.gitignore`, kľúč nikdy nejde do súboru. Lokálny `pre-commit` hook to stráži, `--no-verify` nepoužívať.
- Overiť, že Pages sa postavili a všetky súbory vracajú HTTP 200: `python demo\kontrola.py stranka --url https://altorealestate.github.io/kupelna-konfigurator/`.

## 5. Chyby, ktoré sa už stali

| Čo sa stalo | Príčina | Poistka teraz |
|---|---|---|
| Svetlé škvrny okolo batérií na tmavom obklade (1K) | vrstva z pôvodného obkladu nesie jeho farbu | prvok sa vkladá na každý obklad a okraje sa prefarbia (`Prefarbi`) |
| Chýbal výtok vane, hadica | prompt nevymenoval časti | prompt vymenúva všetky časti produktu |
| Sprcha vychádzala z inej steny (1K) | model sprchu nakreslil podľa produktovej fotky | sprcha Pulsify S 260 sa iba prefarbí |
| Batérie skákali veľkosťou a polohou pri zmene obkladu | každý obklad mal vlastnú generáciu batérií | `naObkladoch`: vygenerovať raz, tie isté pixely na každý obklad, jadro sa obnoví |
| Duch chrómovej sprchy na Graphite | chróm odráža tmavú stenu, rozdiel je malý | vrstva vždy pokrýva celý obrys starého aj nového prvku (footprint) |
| Biely pruh cez okrúhle umývadlo | vrstva batérií bola nad umývadlom | umývadlo je navrchu (z 4), batéria sa vyreže nad okrajom misy (`stlpec`) |
| Schodík v okraji misy | pevný výrez stĺpca | okraj misy sa hľadá automaticky v maske prvku |
| Vrstvy nesedeli v 4K | model scénu preráma (zoom 0,5–2,5 %, posun až 40 px) | `Zarovnanie.Najdi` + lokálny posun v každom `roi` |
| Dlažba prekreslila žľab | generácia prekreslí celý obrázok | `bezObjektov: ["zlab"]` + `pas` žľabu |
| V tieni pod policou presvitala stará dlažba | podobný tón starej a novej dlažby | `kluc-dlazba` (podlaha natretá na zeleno) |
| Biele umývadlo sa nedalo vyrezať, `prazdne-umyvadlo` nechalo ducha | biela na svetlej stene | zelený kľúč `<variant>#kluc` |
| Priesvitné zvyšky starých batérií | AI ich pri dočistení nechala | staré batérie sa pred vložením hrubo zamažú |
| Svetlá aura okolo bronzu; prvá oprava rozmazala sivú na vani | okraje niesli farbu pôvodnej steny | `Prefarbi` pixel po pixeli podľa `prazdne-baterie` |
| Graphit „zapustil“ umývadlo do police | prompt obkladu policu neopisoval | prompt výslovne drží tvar police a umývadlo na nej |
| Obdĺžnik na polici pod umývadlami | AI prefarbila policu nerovnomerne | riadky police z variantu (`polica`) + doladenie tónu (`Vyrovnanie`) |
| Šev na okraji `roi` (Travertine) | AI prekreslila stenu iným vzorom | vrstva len v obryse starého a nového prvku |
| Zvyšky Savoy na Calacatte (2×) | tenké zvyšky starej misy AI brala ako dizajn | staré umývadlo sa celé zmaže podľa `kluc-umyvadlo` |
| Svetlé fľaky pri prírubách vane | obnovené jadro zahŕňalo tiene | jadro len z pevnej časti (rozdiel 45–75) |
| Rozeta sifónu posunutá, chrómový duch | voľný prompt prefarbenia | prompt: rozeta vycentrovaná, žiadny okraj |
| Umývadlová batéria otočená bokom | model ju otočil podľa produktovej fotky | otočenie na pomocnom kroku `baterie-black-sifon` → `baterie-black` |
| **Doplnky na polici zdeformované** (pribudla fľaša, iný dávkovač, z uteráka hubka) | obklad = celý obrázok, doplnky nič nezakryje; kontrola pozerala len obklad a batérie | AI doplnky z obkladu odstráni (`prazdne-doplnky@obklad`), vložia sa pôvodné; doplnky sú v zozname kontroly |
| Vloženie doplnkov + dočistenie cez AI | AI dokreslila druhý podnos a vetvičku | pri doplnkoch AI len maže, nevkladá |
| Pás pôvodnej dlažby za žľabom aj pred ním | z dlažby sa vyrezávala celá plocha, kde sa líši grafitový žľab, a ten je širší (až k stene) a dlhší ako pôvodný | `pas` žľabu: dlažba je v ňom celá (doplnená z riadkov pod ním), každý žľab, aj pôvodný, má vrstvu len s kovom |
| Umývadlová batéria asi 1,5× väčšia ako pôvodná (výška aj hrúbka tela) | prompt žiadal Tecturis S 240 Fine („240“ = vysoká verzia) | `mierka` variantu: batéria sa zmenší 0,67× okolo bodu, kde stojí na polici, na miesto pôvodnej; stena za ňou z `prazdne-baterie` prefarbená na obklad (podklad obkladu má pôvodnú batériu o pár px inde, kľúč umývadla je o ~13 px vyššie ako hrana misy → `okraj`) |
| Odraz v zrkadle s pôvodným obkladom | prompt obkladu držal „the round mirror and its reflection“ | `zrkadlo@<obklad>` (odraz prekreslený na obklade bez doplnkov), zo zrkadlovej generácie sa berie len vnútro zrkadla |
| **Obklady v 4K zrnité, „horšie ako prvá 1K verzia“** (kolega 14. 10.) | model v 4K kreslil kameň ako reliéf so svetlými zrnkami, travertín ako vystúpené vlny; referenčné fotky majú len 640 px; v 1K na reliéf nemal rozlíšenie | prompt rovnej hladkej platne + obklady a všetko na nich v 2K (kolega vybral 15. 10. z testu 1K / 4K / 4K a 2K s novým promptom); povrch obkladu je v kontrolnom zozname |
| **Umývadlová batéria na Calacatte, Graphite a Travertine: svetlý obrys s rozmazanou čiernou škvrnou** (používateľ 15. 10., po pregenerovaní obkladov v 2K) | vstup `@obklad` už mal zmenšenú batériu (`mierka`), `zostav` ju zmenšil druhýkrát; kontrola po zostavení pozerala celý výrez batérií, kde je umývadlová batéria malá | `zmensene: true` vo `vysledky.json` → bez druhého zmenšenia; kontrola v kroku 3 aj s `--oblast bateria-umyvadlo` |
| **Dlažba Stone Life Graphite nie je totožná s produktom** (používateľ 15. 10.): svetlejšia, do olivova, zrnitý reliéf | kie 4K, rovnaká príčina ako pri obkladoch; referencia má len 407 px | dlažba v 2K, prompt rovnej hladkej dlaždice a tón produktu slovami |
| Svetlý lem okolo nôh stoličky na tmavej dlažbe, svetlejšie miesto pod sedadlom (používateľ 15. 10.) | stolička je v dlažbe aj v podklade rovnaká, mäkký okraj masky z rozdielu sa preto stratil pár px pred ňou a presvitala pôvodná svetlá dlažba z obrázka obkladu | vrstva dlažby až po okraj zeleného kľúča (`kluc-dlazba`); kontrola `--oblast stolicka` na tmavej dlažbe |
| Pás za žľabom na tmavej dlažbe svetlejší a rozmazaný, na pravom konci tmavý zárez so svetlým rámom (používateľ 15. 10.) | celý pás sa vypĺňal riadkami spred žľabu posunutými nahor (odlesky, pri pravom konci rám zásteny); kov pôvodného žľabu mal mäkký okraj s jeho svetlou dlažbou | výplň len pod kovom pôvodného žľabu, inde vlastná dlažba generácie; kov pôvodného žľabu len pevná časť + 2 px |
| Batéria na Graphite väčšia ako na ostatných obkladoch, svetlá páka | model pri dočistení batériu zväčšil (~1,2×) a páku prekreslil; jadro sa obnovuje len vnútri, tenká páka doň nepatrí | `Set-ScaledCleanup`: batéria zo vstupu generácie, zväčšený okraj nahradí uvoľnená stena |
| Zvyšok starej misy vedľa Savoy (Travertine), schodík na polici (Graphite) | nie výrez doplnkov (pôvodný odhad), ale samotná AI: úzky pruh starej misy vedľa širokej Savoy nechala ako dizajn, pri tmavej stene prefarbila zadný okraj police do teplej | `pozadieZ`: miesto po starej mise mimo Savoy z výsledku užšieho okrúhleho umývadla na tom istom obklade; `polica` už od zadnej hrany police |
| Výsledok `prazdna-scena` zmizol z `vysledky.json` (15. 10.) | dve session spustili `generuj.ps1` súčasne, druhá uložila celý svoj (starší) zoznam | `Save-Results` zapisuje len nové výsledky, zlúčené so stavom na disku; obrázok ostal vo `vystupy`, záznam sa doplnil bez generovania |
| demo2: chrómový sifón takmer chýbal | v tieni pod policou má chróm tón steny, rozdiel voči prázdnej scéne ho nenašiel | zelený kľúč pôvodných batérií `kluc-baterie` |
| demo2: béžová a hnedá aura, pás medzi tyčou a hadicou, ružový obdĺžnik pod policou (bronz) | stena generácie variantu je inak tónovaná ako prázdna scéna aj `prazdne-baterie` (čierna oranžová, bronz ružový), škáry a okraj vane o pár px inde; obrys z rozdielu zobral stenu | kľúč každého variantu (`<variant>#kluc`), stena z tej istej generácie, pozadie aj to, čo sedí s prázdnou scénou do ±9 px, opacita okraja projekciou, slabé okraje vo farbe predmetu |
| demo2: svetlá linka pod umývadlom | rozmazanie pri výpočte tieňa roztieklo tmavý okraj misy na policu | tieň z rozmazania bez pixelov predmetu |
| **demo2: umývadlá bez zadnej hrany a vnútra misy, pod misou svetlá linka bez tieňa, chýbajúce tyčinky difuzéra a svetlé fľaky pri váze** (používateľ 15. 10., Savoy + bronz na pôvodnom obklade) | Mis: pevný orez vrchu kľúča 18 px (kľúč Savoy sedí presne), rez stĺpca batérie aj cez misu. Tieň: odhad z vlastnej generácie na úzkej polici; kontaktná čiara rozmazaná na 9 px; `$r` v `New-Layer` prekryl `$R`, takže dosah bol 2 px. Doplnky: na pôvodnom obklade celé okolie doplnkov z prázdnej scény, tyčinky v maske nie sú. Kontrola po demo2 pozerala len celé výrezy, nie zväčšenú misu a doplnky. | Orez kľúča meraný po stĺpcoch (`OrezKluc`). Tieň umývadiel voči prázdnej scéne (`tienZoSceny`), ostrý kontaktný tieň a správny dosah. Pôvodný obklad nechá okolo doplnkov fotku. Tyčinky podľa farby (`tenke`). Kontrola: zväčšená misa (vrch aj spodok) a doplnky na každom obklade. |
| **demo2 po prvej oprave: šedý tieň umývadla, zubatá a miestami zrezaná horná hrana, priesvitný výpust** (používateľ 15. 10., Savoy + bronz a okrúhle + čierna na pôvodnom obklade) | Tieň bol čierny s alfou: béžová polica stmavená rovnomerne vo všetkých kanáloch je sivá, nie hnedá. Kontaktný pás pod misou (3 px) rozmazanie rozriedilo pod prah. Horná hrana: orez kľúča po celých riadkoch, medián stĺpcov (schody), na okrúhlej mise ho projekcia stena–misa zrezala o 5 px (misa má pri zadnej hrane farbu steny), pod misou odhad steny zmiešal policu s prednou hranou. Výpust: kovový, v kľúči tmavozelená diera. Porovnanie s generáciou bez lokálneho posunu kategórie ukazovalo falošný posun o 1–2 px. | Farebný tieň na polici (`farebnyTien`), kontaktný tieň bez rozmazania. Vrstva umývadla = kľúč s vrchom posunutým na nameranú hranu (`OrezKluc` aj nad kľúč, vyhladenie podľa farby lemu), bez projekcie. Diery v kľúči sa zaplnia (`Diery`). Kontrola: zväčšený vrch, spodok a výpust každej misy voči generácii zarovnanej s `$kat`, aj na Graphite. |
| **demo2: Savoy „má vadu pri umývadlovej batérii“** (používateľ 15. 10., bronz aj čierna) | V pásiku za batériou (`stlpec`) sa hrana misy nemerala, dopočítala sa ako vzdialenosť od vrchu kľúča: o 3 px vyššie ako lem, tvrdý okraj so schodíkom a pásom steny z generácie (na Graphite béžový). Pod pätou pôvodnej chrómovej batérie je kľúč natretý len čiastočne (lem polopriesvitný, presvital tieň novej batérie) a lem má tmavú pätu starej batérie. | Hrana sa meria aj v pásiku, stĺpce s batériou (+3 px) sa dopočítajú vo výške a ich lem sa prevezme zo susedov. Kontrola: zväčšená päta batérie pri každom umývadle s každou batériou, aj na Graphite. |

## 6. Zámerné rozhodnutia (nemeniť bez dohody)

- Generovanie cez OpenAI `gpt-image-2.5-sunburst` (predtým kie.ai GPT 2.5 flare), demo v 4K.
- Obklady v 2K s promptom rovnej hladkej platne (kolega 15. 10. 2026: z porovnania 1K, 4K a nového promptu v 4K a 2K je 2K najlepšie). 4K pre obklady nevracať bez nového porovnania s ním. Dlažba rovnako v 2K.
- Bronz = prefarbená čierna batéria (rovnaký tvar). Sprcha sa iba prefarbí.
- Sifón a krytka prepadu majú farbu batérií. V katalógu nie sú, takže je to predpoklad, ktorý môže potvrdiť kolega.
- Chrómová vzpera sklenenej zásteny ostáva chrómová (patrí k sklu, nie k Hansgrohe).
- Stránka bez vysvetľujúcich textov, bez galérie testov a bez porovnania s pôvodnou. Výnimka na požiadanie: `demo2` má prepínač Nový postup / Doterajší (porovnanie postupov pri tej istej zostave).

## 7. Otvorené chyby

Žiadne. Chyby nahlásené 14. 10. 2026 (pás za žľabom, odraz v zrkadle, veľkosť batérie, konce Savoy, zrnité obklady) a 15. 10. 2026 (umývadlová batéria na nových obkladoch) sú opravené, pozri tabuľku v časti 5. Kontrola v kroku 2 a 3 preto zahŕňa aj pás podlahy za žľabom, odraz v zrkadle, veľkosť batérie voči pôvodnej, zväčšený výrez umývadlovej batérie, konce širokého umývadla a povrch obkladu.

Poznámky k zrnitosti obkladov (pre prípad, že sa vráti): zrnitosť bola už v surovom 4K výstupe, JPEG na stránke sa od neho takmer nelíšil. Vysokofrekvenčná energia steny Graphit pri zobrazení 1440 px: 4K kie 6,4, 1K 4,4, pôvodná vizualizácia 2,2. Stlmenie filtrom (frekvenčné oddelenie, 30 %) zrnká zmierni, reliéf nie. Test promptu je vo `vystupy\test-obklad\` (zmenil sa prompt aj model naraz).

## 8. Známe drobnosti (neopravené)

- Bronzový sifón je o niečo tenší ako čierny.
- Pri čiernom vaňovom termostate na Graphite ostávajú slabé svetlé škvrny pri rozetách.
- Slabé čiary po starých prvkoch sú viditeľné až pri asi 4× zväčšení.
- Pravý okraj Savoy na Graphite a Travertine má pri zväčšení tenký svetlejší lem (AI ju na obklade nakreslila o pár px širšiu, jadro sa obnovuje len vnútri).
- Okolo batérie na pôvodnom obklade je slabo svetlejší obdĺžnik (AI prekreslila stenu, vrstva ju čiastočne berie).
- V okrúhlom umývadle je pod batériou na vnútornej stene misy svetlejší pás. Je tam aj s pôvodnou chrómovou batériou, nakreslil ho model pri generovaní umývadla.
- Pri rozete sifónu na Graphite a Travertine slabý svetlý oblúk starej chrómovej rozety (viditeľný až pri ~3× zväčšení). Na Graphite pri 4× zväčšení tenký svetlý prúžok vľavo od tela umývadlovej batérie.
- demo2: chróm (pôvodné batérie) odráža béžovú stenu pôvodnej vizualizácie, na Graphite je svetlejší a teplejší ako v doterajšom postupe a tenká hadica má slabý svetlý lem. Lesklý chróm nemôže byť jedna vrstva pre všetky obklady bez úpravy odrazu.
- demo2: na pôvodnom obklade má stena v okolí predmetov textúru prázdnej scény (iná generácia); pôvodná zostava sa od pôvodnej vizualizácie líši priemerne o 1,67 z 255.
- demo2: tieň umývadla na polici je z generácie umývadla, na iných obkladoch sa nemení (AI ho v doterajšom postupe kreslí na každom obklade zvlášť); pri difuzéri má malú medzeru (vrstvy produktov vynechávajú doplnky). Kontaktná čiara pod okrúhlou misou je pri 4–5× zväčšení mierne prerušovaná. Pôvodné obdĺžnikové umývadlo má pod batériou sivý pás (odraz chrómovej batérie z pôvodnej vizualizácie, aj v doterajšom postupe) a jeho ľavý koniec pri difuzéri je na obkladoch mierne rozmazaný (vložené doplnky).

## 9. Prostredie

- Pasce PowerShellu sú v CLAUDE.md.
- Python 3.13 (používateľská inštalácia `%LOCALAPPDATA%\Programs\Python\Python313`, v PATH pred stubom z WindowsApps) s numpy, Pillow, OpenCV a Playwright. Procesy spustené pred inštaláciou (VS Code a jeho terminály) `python` nevidia, kým sa VS Code nereštartuje; dovtedy plná cesta `& "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe"`. `cv2.imread`/`imwrite` neotvoria cestu s diakritikou („Pracovná“, „Kupelňa“), preto `cv2.imdecode(np.fromfile(…))` / `imencode(…).tofile(…)` (ako v `kontrola.py`). Slúži na kontrolné výrezy, porovnania a screenshoty stránky v ľubovoľnej šírke (Playwright s nainštalovaným Edge: `p.chromium.launch(channel='msedge')`, bez sťahovania prehliadača). Pipeline (`generuj`, `zostav`, `obrazky.cs`) ostáva v PowerShelli a C#.
- Node nie je nainštalovaný, netreba ho.
