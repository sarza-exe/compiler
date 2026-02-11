# Kompilator Języka Imperatywnego

Projekt kompilatora prostego języka imperatywnego, generującego kod dla dedykowanej maszyny wirtualnej. Narzędzie zostało zbudowane z wykorzystaniem generatorów **BISON** oraz **FLEX** w środowisku **C++**.

## 📁 Struktura plików

* `parser.y` – rdzeń projektu. Specyfikacja gramatyki w BISON-ie. Przechodzi przez gramatykę i generuje kod maszyny wirtualnej. Sprawdza czy w kodzie nie ma błędów i je wypisuje na wyjściu.
* `lexer.l` – analizator leksykalny FLEX kodu wejściowego.
* `codeGenerator.hh` – służy do generowania kodu, tworzenia i naprawiania instrukcji skoku (backpatching) oraz generowania fragmentów kodu do mnożenia / dzielenia / generowania stałych.
* `symbolTable.hh` - służy do tworzenia i zarządzania informacjami o zmiennych, parametrach, iteratorach oraz procedurach.
* `main.cc` - otwiera / zamyka pliki i wywołuje parser.
* 
`Makefile` – skrypt budujący projekt.

## 🏆 Ranking i Stabilność

Kompilator brał udział w rankingu wydajności i jakości, zajmując **26. miejsce na 79** uczestników.

**Niezawodność:** Program przeszedł **100% testów konkursowych** (28/28 ukrytych scenariuszy), co potwierdza jego stabilność i odporność na błędy logiczne w kodzie źródłowym.
 
**Zgodność:** W pełni obsługuje zaawansowane elementy języka, takie jak parametry procedur przekazywane przez referencję (IN-OUT), stałe (I) oraz nieokreślone parametry wyjściowe (O).



## ⚙️ Kluczowe Funkcjonalności

**Efektywna Arytmetyka:** Implementacja operacji mnożenia, dzielenia oraz liczenia reszty wykonuje się w **czasie logarytmicznym** względem wartości argumentów. Unika to kosztownych pętli opartych na prostym dodawaniu/odejmowaniu.

**Obsługa skoków:** Program emituje i naprawia (backpatching) instrukcje skoków kodu maszyny wirtualnej potrzebnych do instrukcji warunkowych, wywoływania procedur oraz pętli `FOR`, `WHILE`, `REPEAT-UNTIL`.

**Zarządzanie Pamięcią:** Pełna obsługa tablic z dowolnym zakresem indeksowania np. `tab[10:20]` oraz lokalnych iteratorów pętli `FOR`. Poprawne przypisywanie referencji przy wywoływaniu procedury.
 
**Analiza Błędów:** Kompilator precyzyjnie sygnalizuje błędy semantyczne, takie jak redefinicja zmiennych, użycie niezadeklarowanych identyfikatorów czy próba modyfikacji stałych lub iteratorów.



## 🚀 Uruchomienie

Zgodnie z wymaganiami, projekt zawiera plik `Makefile`.

1. **Kompilacja projektu:**
```bash
make

```


2. **Uruchomienie kompilatora:**
```bash
./kompilator <plik_wejsciowy> <plik_wyjsciowy>

```

---

**Autor:** Sara Żyndul 