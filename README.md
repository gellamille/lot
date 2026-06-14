# Gellamille V5

A V5 új moduljai:

- LOT-alapú készletkezelés
- partnerek
- szállítmányok
- egy LOT több szállítmányhoz és partnerhez rendelhető
- LOT-onként külön darabszám
- lefoglalt, kiszállított és elérhető készlet
- szállítmány státuszok: piszkozat, lezárt, kiszállított, sztornózott
- szállítmány sztornózásakor a foglalás felszabadul

A partneri rendelési felület ebben a verzióban nincs benne.

## Telepítés

### 1. Supabase

Futtasd le egyszer:

`gellamille_lot_v5_migration.sql`

A V4 migrációnak előtte már futnia kell.

### 2. GitHub

A ZIP kicsomagolt tartalmát töltsd fel a repository gyökerébe, majd Commit changes.

### 3. Vercel

A GitHub commit után a Vercel automatikusan új deploymentet készít.

Framework: Other  
Build Command: üres  
Output Directory: üres


## V5.1 javítás

- Oldalfrissítéskor nem villan fel tévesen a belépőoldal.
- A Supabase-munkamenet és az adatbázis betöltéséig külön töltőképernyő jelenik meg.
- Kapcsolati hiba esetén egyértelmű hibaüzenet és Újrapróbálás gomb látható.
- Ehhez a javításhoz nem szükséges új Supabase SQL-migráció.


## V5.2 hálózati állapot

- Internetkapcsolat hiányakor külön offline üzenet jelenik meg.
- Betöltés közben nem marad végtelen töltésben.
- A már megnyitott alkalmazás tetején offline figyelmeztetés látható.
- A kapcsolat helyreállásakor a rendszer visszajelez és újrapróbálja a betöltést.
- Ehhez nem szükséges Supabase SQL-migráció.


## V5.3 teljesítményjavítás

- A teljes képernyős töltés csak 400 ms-nál hosszabb munkamenet-ellenőrzésnél jelenik meg.
- Belépett felhasználónál az alkalmazás váza azonnal megjelenik.
- Kezdetben csak az ízek, felelősök és LOT-ok töltődnek be.
- A készlet, partnerek és szállítmányok csak az adott fül megnyitásakor töltődnek be.
- Megszűnt a munkamenet miatti dupla adatbázis-lekérés.
- A PWA saját fájljai gyorsítótárból azonnal betöltődnek, majd háttérben frissülnek.
- Supabase SQL-migráció nem szükséges.


## V5.4 offline adatfrissesség

- Offline módban tartós figyelmeztető sáv jelenik meg.
- A rendszer kiírja az utolsó sikeres adatfrissítés időpontját.
- Egyértelműen jelzi, hogy az adatok elavultak lehetnek.
- Új adatok csak internetkapcsolat után jelennek meg.
- Offline módban a létrehozási, módosítási, sztornózási és szállítmánykezelési műveletek blokkolva vannak.
- Kapcsolat-visszatéréskor automatikus adatfrissítés indul.
- Ehhez nem szükséges Supabase SQL-migráció.


## V5.5 összevont kiadás

Ez az egyetlen csomag tartalmazza:

- a V5.3 teljesítményjavításait
- a V5.4 offline adatfrissesség-jelzését
- az utolsó sikeres szinkron időpontját
- az offline módosítások blokkolását
- az új felelős személy külön modal ablakban történő hozzáadását

Supabase SQL-migráció nem szükséges.
