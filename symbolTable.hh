#pragma once
#include <map>
#include <stdexcept>
#include <string>
#include <iostream>
#include <climits>
#include <vector>

struct Symbol {
    std::string name;
    unsigned long long memory_address; // Adres w pamięci maszyny wirtualnej
    bool is_array = false; 
    unsigned long long array_start; // Początek zakresu tablicy (np. -10)
    unsigned long long array_end;
    bool is_param = false;          // jeśli true to ładujemy adres
    bool is_I = false;              // I oznacza zmienną stałą w procedurze t.j. nie można jej modyfikować
    bool is_O = false;              // O oznacza zmienną OUT w procedurze t.j. ma początkowo nieokreśloną wartość
    bool is_T = false;              // T oznacza table w procedurach
    bool is_initialized = false;    // tylko dla zmiennych (nie dla tablic)
    bool is_iterator = false;       // czy jest iteratorem pętli FOR
};

struct ForLoopInfo {
    std::string iteratorName;
    unsigned long long iteratorAddr;// Adres iteratora
    unsigned long long limitAddr;   // Adres ukrytej zmiennej z limitem
    unsigned long long startLabel;  // Etykieta początku pętli (skok powrotny)
    unsigned long long endLabel;    // Etykieta końca pętli (skok wyjścia)
    bool is_downto;                 // true jeśli DOWNTO, false jeśli TO
};

struct Procedure {
    std::string name;
    unsigned long long returnAddressVar;    // Zmienna w VM która przechowuje adres powrotu z procedury
    unsigned long long startLable;          // Numer linii w VM, gdzie procedura się zaczyna
    // Lista parametrów w kolejności deklaracji - potrzebne do walidacji wywołania
    std::vector<Symbol> parameters;          //SKOPIOWAĆ BO PRZY LEAVE SCOPE USUNA SIE
    std::map<std::string, bool> initialized; // Zapisujemy które zmienne są inicjalizowane w procedurze w razie dalszego przekazywania do innych procedur
}; 

class SymbolTable {
    std::vector<std::map<std::string, Symbol>> scopes; // stos scope'ów procedur i maina
    std::map<std::string, Procedure> procedures;       // mapujemy nazwy do procedur (nazwy procedur nie mogą się powtórzyć)
    std::vector<ForLoopInfo*> forStack;                // stack iteratorów pętli FOR
    unsigned long long memory_offset = 0;              // globalny offset pamięci
    const unsigned long long MEMORY_END = LLONG_MAX/2; // Koniec pamięci VM
    std::string currProcedure = "";                    // nazwa obecnej procedury

public:
    /// @brief Tworzy nowy zakres widoczności (scope) na stosie
    void enterScope(){
        scopes.emplace_back(); // Nowy scope lokalny
    }

    /// @brief Usuwa aktualny zakres widoczności ze stosu i czyści nazwę obecnej procedury
    void leaveScope(){
        scopes.pop_back(); // Wychodzimy ze scopu lokalnego
        currProcedure = "";
    }

    /// @brief Sprawdza czy procedura o podanej nazwie została już zadeklarowana
    /// @param procName nazwa procedury
    /// @return true jeśli procedura istnieje, w przeciwnym razie false
    bool procedureExists(const std::string& procName){
        if (auto search = procedures.find(procName); search != procedures.end())
            return true;
        else return false;
    }

    /// @brief Zwraca nazwę aktualnie przetwarzanej procedury
    /// @return nazwa procedury
    std::string currentProcedure(){
        return currProcedure;
    }

    /// @brief Pobiera etykietę startową (adres kodu) danej procedury
    /// @param procName nazwa procedury
    /// @return numer linii startowej procedury
    unsigned long long getProcedureLable(const std::string& procName){
        if(!procedureExists(procName)) throw std::invalid_argument("Getting lable of unexisting procedure " + procName);
        return procedures[procName].startLable;
    }

    /// @brief Pobiera adres w pamięci zmiennej przechowującej adres powrotu obecnej procedury
    /// @return adres pamięci zmiennej powrotu
    unsigned long long getReturnAddress(){
        return procedures[currProcedure].returnAddressVar;
    }

    /// @brief Rejestruje nową procedurę i alokuje pamięć na jej adres powrotu
    /// @param procName nazwa procedury
    /// @param startLable etykieta początku kodu procedury
    /// @return adres pamięci zarezerwowany dla adresu powrotu
    unsigned long long createProcedure(const std::string& procName, unsigned long long startLable){
        if (procedures.find(procName) != procedures.end()){
            throw std::invalid_argument("Procedure already declared");
        }
        Procedure proc;
        proc.returnAddressVar = memory_offset;
        memory_offset++;
        proc.name = procName;
        proc.startLable = startLable;
        procedures.emplace(procName, std::move(proc)); // albo procedures[procName] = proc;
        currProcedure = procName;
        return proc.returnAddressVar;
    }

    /// @brief Wyszukuje symbol (zmienną lub tablicę) w aktualnym zakresie
    /// @param name nazwa symbolu
    /// @return wskaźnik na strukturę Symbol lub nullptr
    Symbol* getSymbol(std::string name) {
        if (auto search = scopes.back().find(name); search != scopes.back().end())
            return &search->second;
        else return nullptr;
    }

    /// @brief Sprawdza czy parametr procedury jest zainicjalizowany i propaguje inicjalizację na argument wywołania
    /// @param procName nazwa procedury
    /// @param paramName nazwa parametru formalnego
    /// @param arg wskaźnik na symbol argumentu przekazywanego do procedury
    /// @return true jeśli parametr jest oznaczony jako zainicjalizowany
    bool isParameterInitialized(std::string procName, std::string paramName, Symbol *arg){
        bool isInit = procedures[procName].initialized[paramName];
        if(isInit && currProcedure != "") procedures[currProcedure].initialized[arg->name] = true;
        return isInit;
    }

    /// @brief Oznacza zmienną lub parametr jako zainicjalizowany
    /// @param name nazwa zmiennej
    void markInitialized(std::string name){
        Symbol* sym = getSymbol(name);
        if(sym->is_array) return;
        if(sym->is_param){
            procedures[currProcedure].initialized[name] = true;
        }
        sym->is_initialized = true;
    }

    /// @brief Zwraca adres pamięci zmiennej skalarnej. Rzuca błąd jeśli to tablica.
    /// @param name nazwa zmiennej
    /// @return adres w pamięci wirtualnej
    unsigned long long getAddressVar(const std::string& name)
    {
        auto it = scopes.back().find(name);
        if (it == scopes.back().end())
            throw std::invalid_argument("Variable \"" + name + "\" not defined");
        if (it->second.is_array) throw std::invalid_argument(name +" is an array not variable");
        return it->second.memory_address;
    }

    /// @brief Zwraca adres bazowy tablicy. Rzuca błąd jeśli to zmienna skalarna.
    /// @param name nazwa tablicy
    /// @return adres początkowy tablicy w pamięci
    unsigned long long getAddressArr(const std::string& name)
    {
        auto it = scopes.back().find(name);
        if (it == scopes.back().end())
            throw std::invalid_argument("Array \"" + name + "\" not defined");
        if (!it->second.is_array) throw std::invalid_argument(name +" is a variable not an array");
        return it->second.memory_address;
    }

    /// @brief Oblicza adres konkretnego elementu tablicy dla stałego indeksu
    /// @param name nazwa tablicy
    /// @param index stała wartość indeksu
    /// @return obliczony adres pamięci elementu tablicy
    unsigned long long getArrayElementAddress(const std::string& name, unsigned long long index) const {
        auto it = scopes.back().find(name);
        if (it == scopes.back().end())
            throw std::invalid_argument("Array \"" + name + "\" not defined");
        const Symbol& s = it->second;
        if (!s.is_array)
            throw std::invalid_argument("Trying to access \"" + name + "\" through index but \"" + name + "\" is not an array");
        if (index < s.array_start || index > s.array_end)
            throw std::out_of_range("Index " + std::to_string(index) + " not in range for array \"" + name + "\"");
        return s.memory_address + (index - s.array_start);
    }

    /// @brief Pobiera listę parametrów zdefiniowanych dla danej procedury
    /// @param name nazwa procedury
    /// @return wektor symboli parametrów
    std::vector<Symbol> getParameters(const std::string& name){
        if (auto search = procedures.find(name); search != procedures.end()){
            return procedures[name].parameters;
        }
        else{
            throw std::invalid_argument("Procedure not declared");
        }
    }

    /// @brief Waliduje zgodność liczby i istnienia argumentów przy wywołaniu procedury
    /// @param name nazwa wywoływanej procedury
    /// @param args wektor nazw zmiennych przekazywanych jako argumenty
    void setArguments(const std::string& name, std::vector<const char*> args){
        std::vector<Symbol> params = procedures[name].parameters;
        int argsSize = args.size();
        if((int)params.size() != argsSize) throw std::invalid_argument("Wrong number of arguments at call for procedure " + name);

        for (int i = 0; i < argsSize; i++){
            std::string argName = args[i];
            Symbol* arg = getSymbol(argName);
            if(arg == nullptr) throw std::invalid_argument("Trying to call procedure " + name + "with undeclared variable " + name);
            Symbol param = params.at(i);
        }
    }

    /// @brief Deklaruje nowy parametr dla aktualnie definiowanej procedury
    /// @param name nazwa parametru
    /// @param type typ parametru: 'T' (tablica), 'I' (wartość stała), 'O' (wyjście)
    void declareParameter(const std::string& name, char type)
    {
        if (exists(name)) throw std::invalid_argument("Double variable declaration: " + name);
        if (memory_offset + 1 > MEMORY_END) throw std::overflow_error("Run out of memory for variable: " + name);
        
        Symbol s;
        s.name = name;
        s.memory_address = memory_offset;
        s.is_param = true;
        s.is_array = (type == 'T');

        if(type == 'I') s.is_I = true;
        else if(type == 'O') s.is_O = true;
        else if(type == 'T'){
             s.is_T = true;
             memory_offset++; //adres dla indeksu startowego
        }

        if (procedures.find(currProcedure) != procedures.end()) {
            procedures[currProcedure].parameters.push_back(s);
            procedures[currProcedure].initialized[name] = false;
        } else {
            throw std::runtime_error("Internal error: procedure not found");
        }

        scopes.back().emplace(name, std::move(s));
        ++memory_offset;
    }

    /// @brief Rejestruje nową zmienną lokalną w obecnym zakresie i alokuje pamięć
    /// @param name nazwa zmiennej
    void declareVariable(const std::string& name)
    {
        if (exists(name)) throw std::invalid_argument("Double variable declaration: " + name);
        if (memory_offset + 1 > MEMORY_END) throw std::overflow_error("Run out of memory for variable: " + name);
        Symbol s;
        s.name = name;
        s.memory_address = memory_offset;
        s.is_array = false;
        scopes.back().emplace(name, std::move(s));
        ++memory_offset;
    }

    /// @brief Rejestruje iterator pętli oraz ukrytą zmienną limitu
    /// @param name nazwa zmiennej iteratora
    /// @param is_downto flaga określająca kierunek pętli (true dla DOWNTO)
    /// @return wskaźnik na strukturę informacji o pętli
    ForLoopInfo* declareIterator(const std::string& name, bool is_downto)
    {
        if (exists(name)) throw std::invalid_argument("Double variable declaration: " + name);
        if (memory_offset + 1 > MEMORY_END) throw std::overflow_error("Run out of memory for variable: " + name);

        Symbol s;
        s.name = name;
        s.memory_address = memory_offset;
        s.is_array = false;
        s.is_iterator = true;
        s.is_initialized = true;
        scopes.back().emplace(name, std::move(s));

        ForLoopInfo *for_info = new ForLoopInfo();
        for_info->iteratorName = name;
        for_info->iteratorAddr = memory_offset;
        ++memory_offset;
        for_info->limitAddr = memory_offset;
        ++memory_offset;
        for_info->is_downto = is_downto;

        forStack.push_back(for_info);
        return for_info;
    }

    /// @brief Usuwa iterator z obecnego zakresu (używane po zakończeniu generowania pętli)
    void removeIterator(){
        std::string name = forStack.back()->iteratorName;
        if (auto search = scopes.back().find(name); search != scopes.back().end()){
            scopes.back().erase(search);
        }
        forStack.pop_back();
    }

    /// @brief Deklaruje tablicę w obecnym zakresie i rezerwuje stały blok pamięci
    /// @param name nazwa tablicy
    /// @param start indeks początkowy tablicy
    /// @param end indeks końcowy tablicy
    void declareArray(const std::string& name, unsigned long long start, unsigned long long end)
    {
        if(start > end) throw std::invalid_argument("Start index of array \"" + name + "\" greater then end index: " + std::to_string(start) + " > " + std::to_string(end));
        unsigned long long tSize = end-start+1;
        if (memory_offset + tSize > MEMORY_END) throw std::overflow_error("Run out of memory for variable: " + name);
        Symbol sym;
        sym.name = name;
        sym.memory_address = memory_offset;
        memory_offset = memory_offset + tSize;
        sym.is_array = true;
        sym.array_start = start;
        sym.array_end = end;
        sym.is_initialized = true;
        const auto [variable, success] = scopes.back().insert({name, sym});
        if(!success) throw std::invalid_argument("Double declaration " + name);
    }
    
    /// @brief Sprawdza czy zmienna istnieje w obecnym zakresie widoczności
    /// @param name nazwa zmiennej
    /// @return true jeśli zmienna istnieje
    bool exists(const std::string& name)
    {
        if (auto search = scopes.back().find(name); search != scopes.back().end())
            return true;
        else
            return false;
    }
};