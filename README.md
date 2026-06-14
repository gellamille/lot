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
