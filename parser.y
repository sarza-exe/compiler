%code requires { 
#include <vector> 
#include <string>
#include <map>
#include <stdexcept>

using namespace std;

struct Symbol;
struct ForLoopInfo;

struct Identifier {
    char *pid;
    unsigned long long num;
};

// Struktura używana wszędzie tam gdzie są zmienne
struct VariableInfo {
    std::string name;       // nazwa zmiennej
    Symbol *sym;            // referencja dod symbolu zmiennej
    Symbol *ref;            // zapisujemy symbol zmiennej referencyjnej do tablicy np. x dla arr[x]
    bool is_param;          // czy jest parametrem procedury (I, O, T)
    unsigned long long memory_address; // Adres w pamięci maszyny
    bool is_array_ref;      // Czy to referencja do tablicy przez zmienną np. arr[x]
    unsigned long long offset_or_addr; // Adres zmiennej indeksującej (dla arr[x])
    unsigned long long arr_start;
};

// Struktura używana do nieterminala value. Zawsze z niego czytamy, nigdy nie zapisujemy
struct ValueInfo {
    unsigned long long value = 0;
    VariableInfo *var_info;
};

// Argumenty przekazywane do procedury
struct Args{
    std::vector<const char*> arguments;
};

// Struktura do wywoływania procedury przez nazwę i listę argumentów
struct ProcCall{
    Identifier *id;
    Args *args;
};

}

%code provides {
void declare_array(Identifier *id, unsigned long long start, unsigned long long end);
void declare_variable(Identifier *id);
void declare_parameter(Identifier *id, char type);
}


%{
#include <iostream>
#include <string>
#include <vector>

#include "codeGenerator.hh"
#include "symbolTable.hh"
#include "parser.hh"

int yylex( void );
void yyset_in( FILE * in_str );
extern int yylineno;
void yyerror(const char*);

CodeGenerator codeGen;
SymbolTable symbolTable;

/* Funkcja obsługi błędów */
void semantic_error(unsigned long long lineno, char const *s) {
    if(lineno == 0) lineno = (unsigned long long)yylineno;
    std::cerr << "Syntax error on line " << (int)lineno << ": " << s << std::endl;
    exit(-1);
}

/// @brief pobiera listę parametrów procedury name i ustawia referencje do args. Dla tablicy ustawia dodatkową zmienną w której przechowuje indeks startowy tablicy
/// @param name nazwa procedury
/// @param args lista argumentów do przekazania
void set_arguments(const std::string& name, std::vector<const char*> args, unsigned long long line){
    std::vector<Symbol> params = symbolTable.getParameters(name);
    int argsSize = args.size();
    
    if((int)params.size() != argsSize) {
        std::string msg = "Wrong number of arguments at call for procedure " + name;
        yyerror(msg.c_str());
    }

    for (int i = 0; i < argsSize; i++){
        const char *argName = args[i];
        Symbol* arg = symbolTable.getSymbol(argName); // Symbol zmiennej przekazywanej (argumentu)
        
        if(arg == nullptr) {
            std::string msg = "Trying to call procedure with undeclared variable: " + std::string(argName);
            yyerror(msg.c_str());
        }

        Symbol param = params.at(i);
        bool argIsArrayType = arg->is_array || (arg->is_param && arg->is_T);
        
        if (param.is_T && !argIsArrayType) yyerror("Expected array as argument but got scalar variable");
        if (!param.is_T && argIsArrayType) yyerror("Expected scalar variable as argument but got array");
        if (arg->is_O && param.is_I) yyerror("Cannot pass O argument to I parameter");
        if (arg->is_I && !param.is_I) yyerror("Cannot pass I argument to not I parameter");

        if (param.is_T) {
            if (arg->is_param && arg->is_T) {
                codeGen.emit("LOAD", arg->memory_address);
            } else {
                codeGen.generateConstant("a", arg->memory_address);
            }
            codeGen.emit("STORE", param.memory_address);
            
            // Przekazanie INDEKSU STARTOWEGO
            if (arg->is_param && arg->is_T) {
                // Przekazujemy parametr dalej: pobierz start_index z parametru źródłowego
                // Start index leży w komórce obok adresu!
                codeGen.emit("LOAD", arg->memory_address + 1); 
            } else {
                // Przekazujemy zwykłą tablicę: weź jej stały start_index
                codeGen.generateConstant("a", arg->array_start);
            }
            codeGen.emit("STORE", param.memory_address + 1); // Zapisz w drugiej komórce parametru
            
        }
        else{
            if(symbolTable.isParameterInitialized(name, param.name, arg)) arg->is_initialized = true;
            if (arg->is_param) {
            // Przekazujemy dalej parametr Zmienna 'arg' już trzyma ADRES właściwej zmiennej. 
            // Musimy ten adres przepisać do nowego parametru.
            codeGen.emit("LOAD", arg->memory_address); // Wczytaj wartość wskaźnika do Rejestru A
            } else {
                // Przekazujemy zmienną lokalną (np. main x; call p(x);) Musimy przekazać ADRES tej zmiennej w pamięci VM.
                codeGen.generateConstant("a", arg->memory_address);
            }
            // Teraz w Rejestrze A (akumulatorze) mamy adres, na który ma wskazywać nowy parametr.
            // Zapisujemy go w miejscu pamięci przeznaczonym dla parametru procedury.
            codeGen.emit("STORE", param.memory_address);
        }
    }
}

/// @brief deklaruje tablicę
/// @param id nazwa tablicy
/// @param start indeks startowy tablicy (np. 10) tablica nie musi zaczynać się od 0.
/// @param end indeks końcowy tablicy
void declare_array(Identifier *id, unsigned long long start, unsigned long long end)
{
    try {
        symbolTable.declareArray(id->pid, start, end);
    } catch (const std::invalid_argument &e) {
        semantic_error(id->num, e.what());
    }
    free(id->pid);
}

/// @brief deklaruje zmienną
/// @param id nazwa zmiennej
void declare_variable(Identifier *id)
{
    try {
        symbolTable.declareVariable(id->pid);
    } catch (const std::invalid_argument &e) {
        semantic_error(id->num, e.what());
    }
    free(id->pid);
}

/// @brief deklaruje parametr funkcji
/// @param id nazwa parametru
/// @param type typ parametru (I, O, T, '')
void declare_parameter(Identifier *id, char type)
{
    try {
        symbolTable.declareParameter(id->pid, type);
    } catch (const std::invalid_argument &e) {
        semantic_error(id->num, e.what());
    }
    free(id->pid);
}

/// @brief Zapisuje do reg wartość albo adres z info (5,a,tab[5],tab[a]). Rejestr h JEST ZAREZEROWOWANY DO OBLICZEŃ. Rejestr a jest używany do obliczeń. Jeśli mamy gdzieś więcej niż jedną value jednocześnie to tylko ostatnia może zostać zapisana do a. value_to_reg = true to value
/// @param info wszystkie informacje o zmiennej
/// @param reg który rejestr spośród 'a', 'b',... , 'g'
/// @param value_to_reg dla true zapisuje do rejestru wartość zmiennej zapisanej w value. Dla false zapisuje do rejestru adres zmiennej.
void save_to_reg(VariableInfo *info, std::string reg, bool value_to_reg){ 
    if (info->is_array_ref == false) { // x lub arr[5] (stały indeks)
        if (info->sym->is_param && info->sym->is_T) { // Tablica parametrowa(memory_address + 1 zawiera start_index)
            // info->memory_address zawiera: sym->memory_address + index
            unsigned long long constant_index = info->memory_address - info->sym->memory_address;
            // Teraz realizujemy wzór: Adres = Base + (Index - Start)

            codeGen.emit("LOAD", info->sym->memory_address + 1); //ra = startIndex
            codeGen.emit("SWP h"); //rh = startIndex

            codeGen.generateConstant("a", constant_index);
            codeGen.emit("SUB h"); //ra = index - startIndex
            codeGen.emit("SWP h");
            codeGen.emit("LOAD", info->sym->memory_address); //ra = baseaddress
            codeGen.emit("ADD h"); //ra = baseadress + (index - startIndex)

            if(value_to_reg){
                codeGen.emit("SWP h");
                codeGen.emit("RLOAD h #param array const index");
            }
        }
        else { //Zwykła zmienna lub lokalna tablica arr[5]
            if(info->sym->is_param) // Jeśli to zwykły parametr (nie tablica), musimy wyłuskać wartość (dereferencja)
            {
                codeGen.emit("LOAD", info->memory_address);
                if(value_to_reg){
                    codeGen.emit("SWP h");
                    codeGen.emit("RLOAD h #param");
                }
            }
            else{
                if(value_to_reg) codeGen.emit("LOAD", info->memory_address);
                else codeGen.generateConstant("a", info->memory_address);
            }
        }
        if(reg != "a") codeGen.emit("SWP " + reg);
    } else { // arr[x]
        // Adres = AdresBazowy + Wartość(x) - StartIndex
        codeGen.emit("LOAD", info->offset_or_addr); // Załaduj x do ra

        if (info->ref->is_param) { // Jeśli indeks 'x' jest parametrem to ładujemy adres
            if(info->ref->is_O && !info->ref->is_initialized) yyerror("Trying to access O variable");
            codeGen.emit("SWP h");
            codeGen.emit("RLOAD h #load x"); 
        }
        // Teraz w ra mamy liczbę całkowitą będącą indeksem tablicy
        if (info->sym->is_param && info->sym->is_T) {
            if(!info->sym->is_T) yyerror("Accessing parameter as array but array not marked as T");
            // [memory_address] = Adres Bazowy, [memory_address + 1] = Start Index
            // Odejmij StartIndex od wartości indeksu x (arr[x])
            codeGen.emit("SWP h"); //rh = x
            codeGen.emit("LOAD", info->memory_address + 1); //ra = start_index
            codeGen.emit("SWP h"); //ra = x rh = start_index
            codeGen.emit("SUB h"); //ra = x-start_index
            
            codeGen.emit("SWP h"); // Przenieś przesunięcie do 'h', żeby zwolnić 'a'
            codeGen.emit("LOAD", info->memory_address); // Załaduj dynamiczny adres bazowy tablicy
            codeGen.emit("ADD h"); // ra = memory_addres + x - start_index

            if(value_to_reg){
                codeGen.emit("SWP h");
                codeGen.emit("RLOAD h #param");
            }
            if(reg != "a") codeGen.emit("SWP " + reg);
        }
        else{
            long long net_offset = (long long)info->memory_address - (long long)info->sym->array_start;
    
            // rb zawiera net_offset
            if (net_offset > 0) {
                codeGen.generateConstant("h", net_offset); 
                codeGen.emit("ADD h"); // ra = ra + rh = x + arr.memory_address - arr.start_index
            } else if (net_offset < 0) {
                codeGen.generateConstant("h", -net_offset);
                codeGen.emit("SUB h"); // ra = max(ra - rh, 0) 
            }
            
            if(value_to_reg){
                codeGen.emit("SWP h"); // teraz rb zawiera adres
                codeGen.emit("RLOAD h"); // Wczytaj liczbę do ra. ra = p_rh
            }
            if(reg != "a") codeGen.emit("SWP " + reg);
        }
    }
}

/// @brief zapisuje do rejestru wartość zmiennej / liczbę
void save_value_to_reg(ValueInfo *val_info, std::string reg){
    if(reg == "h") yyerror("r_h is reserved for calculations in save_value_to_reg!");
    VariableInfo *info = val_info->var_info;
    if(info == nullptr){
        codeGen.generateConstant(reg, val_info->value);
    }
    else{
        save_to_reg(info, reg, true);
    }
    delete info;
    delete val_info;
}

/// @brief zapisuje do rejestru adres zmiennej / adres
void save_address_to_reg(VariableInfo *info, std::string reg){
    if(reg == "h") yyerror("r_h is reserved for calculations in save_address_to_reg!");
    save_to_reg(info, reg, false);
}

/// @brief tworzy pętle FOR wraz z warunkiem wyjścia z pętli oraz emituje instrukcje skoków
ForLoopInfo* create_for_loop(char* pid, ValueInfo* fromVal, ValueInfo* toVal, bool is_downto) {
    
    ForLoopInfo *info = symbolTable.declareIterator(pid, is_downto); 
    
    // Zapisz wartość początkową (FROM) do iteratora
    save_value_to_reg(fromVal, "a");
    codeGen.emit("STORE", info->iteratorAddr, "FOOOOOOOOOR LOOOOOOOOOP STAAAAAAAAART");
    
    // Zapisz wartość końcową (TO/DOWNTO) do ukrytej zmiennej (limit)
    save_value_to_reg(toVal, "a");
    codeGen.emit("STORE", info->limitAddr);

    int L_start = codeGen.newLable();
    codeGen.defineLable(L_start); // miejsce początku pętli
    codeGen.pushLable(L_start);
    
    if (!is_downto) { // from 0 to 5.
        // Pętla TO (i++). Warunek stopu: Jeśli (iterator - limit) > 0 to KONIEC.
        codeGen.emit("LOAD", info->limitAddr);
        codeGen.emit("SWP b");
        codeGen.emit("LOAD", info->iteratorAddr);
        codeGen.emit("SUB b"); // acc = iterator - limit
    } else { // from 5 down to 2
    // from 5 downto 0 
        // Pętla DOWNTO (i--). Warunek stopu Jeśli (limit - iterator) > 0 to KONIEC.
        codeGen.emit("LOAD", info->iteratorAddr);
        codeGen.emit("SWP b");
        codeGen.emit("LOAD", info->limitAddr);
        codeGen.emit("SUB b");  // acc = limit - iterator
    }

    int L_end = codeGen.newLable();
    codeGen.emitLable(L_end, "JPOS");
    codeGen.pushLable(L_end);
    
    // info->startLabel = startLabel;
    // info->endLabel = jumpInstrIndex;
    
    return info;
}

const std::string JPOS_lable = "JPOS";
const std::string JZERO_lable = "JZERO";

%}

// wyświetla błędy semantyczne np. brak średnika
%define parse.error verbose

/* Definicja typów danych przekazywanych między regułami */
%union {
    unsigned long long num; /* Dla liczb (64-bit)  */
    char type;
    Identifier *id;
    VariableInfo *var_info;
    ValueInfo *val;
    Args *args;
    ProcCall *procCall;
    const std::string *lable;
    ForLoopInfo* loop_info;
}


%token <num> NUM
%token <id> PIDENTIFIER

%type <var_info> identifier
%type <lable> condition
%type <val> value
%type <procCall> proc_call
%type <type> type
%type <args> args
%type <loop_info> for_start

%token ERROR

%token PROCEDURE IS IN END PROGRAM
%token IF THEN ELSE ENDIF
%token WHILE DO ENDWHILE
%token REPEAT UNTIL
%token FOR FROM TO DOWNTO ENDFOR
%token READ WRITE

%token ASSIGN
%token EQ NEQ  
%token GT LT GE LE 
%token COMMA COLON SEMICOLON
%token LPAREN RPAREN LBRACKET RBRACKET
%token T
%token I_CONST O_VAR 

%token PLUS MINUS MULT DIV MOD

%%

// koniec programu ma instrukcje końca HALT
program_all:
    procedures main {codeGen.emit("HALT");}
    ;

// Deklaracja nowej procedury, wejście do nowego zakresu widoczności (scope'u), zapisanie adresu powrotu z procedury
procedure_head: PROCEDURE PIDENTIFIER {
    if(symbolTable.procedureExists($2->pid)) yyerror("Procedure already declared");
    unsigned long long returnAddress = symbolTable.createProcedure($2->pid, codeGen.getCurrentLine());
    symbolTable.enterScope();
    codeGen.emit("STORE", returnAddress);
}

// Po zakończeniu procedury, ładuje adres powrotu i wraca RTRN
procedures:
    procedures procedure_head proc_head IS declarations IN commands END {
        codeGen.emit("LOAD", symbolTable.getReturnAddress());
        codeGen.emit("RTRN #" + symbolTable.currentProcedure());
        symbolTable.leaveScope();
        }
    | procedures procedure_head proc_head IS IN commands END {
        codeGen.emit("LOAD", symbolTable.getReturnAddress());
        codeGen.emit("RTRN #" + symbolTable.currentProcedure());
        symbolTable.leaveScope();
        }
    | %empty
    ;

// Deklaracja parametrów procedury
proc_head:
    LPAREN args_decl RPAREN;

// Deklaracja kolejnych parametrów procedury
args_decl:
    args_decl COMMA type PIDENTIFIER { declare_parameter($4, $3);}
    | type PIDENTIFIER { declare_parameter($2, $1); }
    ;

type:
    T {$$='T';}
    | I_CONST {$$='I';}
    | O_VAR {$$='O';}
    | %empty {$$='N';}
    ;

// wejście w scope dla main
main_start: PROGRAM IS { 
        symbolTable.enterScope(); //enter main scope
        int L_end = codeGen.popLable();
        codeGen.defineLable(L_end);
    }

main:
    main_start declarations IN commands END
    | main_start IN commands END
    | ERROR { yyerror(""); }
    ;

// deklaracja kolejno zmiennej i tablicy
declarations:
    declarations COMMA PIDENTIFIER{ declare_variable($3);}
    | declarations COMMA PIDENTIFIER LBRACKET NUM COLON NUM RBRACKET { declare_array($3, $5, $7);}
    | PIDENTIFIER { declare_variable($1);}
    | PIDENTIFIER LBRACKET NUM COLON NUM RBRACKET { declare_array($1, $3, $5);}
    ;

commands:
    commands command
    | command
    ;
 
 // Pomocniczy nieterminal, wstawia *$1 label i pushLable(label)
if_start:
    condition {
      int L_else = codeGen.newLable();
      codeGen.emitLable(L_else, *$1);
      codeGen.pushLable(L_else);
    };

then_block: THEN commands;

// tworzy pętle for
for_start:
    FOR PIDENTIFIER FROM value TO value DO {
        $$ = create_for_loop($2->pid, $4, $6, false);
    }
    | FOR PIDENTIFIER FROM value DOWNTO value DO {
        $$ = create_for_loop($2->pid, $4, $6, true);
    }
    ;

// To jest miejsce po wykonaniu then_block
then_tail: 
    { 
        int L_else = codeGen.popLable();
        int L_end  = codeGen.newLable();
        codeGen.emitLable(L_end, "JUMP"); // jump za ELSE
        codeGen.defineLable(L_else);// definuj poczatek ELSE
        codeGen.pushLable(L_end);
    } ELSE commands ENDIF {
        int L_end = codeGen.popLable();
        codeGen.defineLable(L_end);
    }
  | ENDIF {//bez ELSE
        int L_end = codeGen.popLable();
        codeGen.defineLable(L_end);
    };

// Rdzeń parsera, są tu wszystkie komendy języka
command:
    identifier ASSIGN expression SEMICOLON { 
        // v := expr, r_b zawiera adres v
        VariableInfo *info = $1;
        if(info->sym->is_I) yyerror("Cannot modify constant I variable");
        if(info->sym->is_iterator) yyerror("Cannot modify FOR iterator");

        codeGen.emit("SWP f");
        save_address_to_reg(info, "b");
        codeGen.emit("SWP f"); 
        codeGen.emit("RSTORE b"); // r_a zawiera wartość expression (policzone w expr)
        symbolTable.markInitialized(info->name);
        delete info;
    } 
    | IF if_start then_block then_tail //działa
    | WHILE{
            int L_start = codeGen.newLable();
            codeGen.defineLable(L_start); // miejsce początku pętli
            codeGen.pushLable(L_start); // zapamiętaj start (będzie potrzebny do JUMP)
        } condition{
            int L_end = codeGen.newLable();
            codeGen.emitLable(L_end, *$3);
            codeGen.pushLable(L_end);
        } DO commands ENDWHILE {
            int L_end = codeGen.popLable();
            int L_start = codeGen.popLable();
            codeGen.emitLable(L_start, "JUMP"); // skocz z powrotem na początek
            codeGen.defineLable(L_end);
        }
    | REPEAT{
            int L_start = codeGen.newLable();
            codeGen.defineLable(L_start); // miejsce początku pętli
            codeGen.pushLable(L_start);
        } commands UNTIL condition SEMICOLON {
            int L_start = codeGen.popLable();
            codeGen.emitLable(L_start, *$5 );
        }
    | for_start commands ENDFOR  {
        ForLoopInfo* info = $1;
        int L_end = codeGen.popLable();

        if (info->is_downto) { // from 5 to 0.
            // Pętla TO (i++). Warunek stopu: Jeśli (iterator - limit) > 0 to KONIEC.
            codeGen.emit("LOAD", info->limitAddr);
            codeGen.emit("SWP b");
            codeGen.emit("LOAD", info->iteratorAddr);
            codeGen.emit("SUB b"); // acc = iterator - limit
            codeGen.emitLable(L_end, "JZERO");
        }
        
        codeGen.emit("LOAD", info->iteratorAddr, "FOOOOOOOOR LOOOOOOOP EEEEEEEEEEENDDDD AT NEXT JUMP");
        
        if (info->is_downto) codeGen.emit("DEC a"); 
        else codeGen.emit("INC a");
        
        codeGen.emit("STORE", info->iteratorAddr);
        
        int L_start = codeGen.popLable();
        codeGen.emitLable(L_start, "JUMP"); // skocz z powrotem na początek
        codeGen.defineLable(L_end);

        symbolTable.removeIterator();
        delete info;
    }
    | proc_call SEMICOLON {
        if(!symbolTable.procedureExists($1->id->pid)) yyerror(("Calling undeclared procedure \"" + std::string($1->id->pid) + "\"").c_str());
        if(symbolTable.currentProcedure() == $1->id->pid) yyerror(("Recursive call for procedure \"" + std::string($1->id->pid) + "\"").c_str());
        unsigned long long procLable = symbolTable.getProcedureLable($1->id->pid);
        set_arguments($1->id->pid, $1->args->arguments, $1->id->num);
        free($1);
        codeGen.emit("CALL", procLable);
    }
    | READ identifier SEMICOLON {
        VariableInfo *info = $2;
        
        if (info->is_array_ref == false && info->sym->is_param == false) { // x lub arr[5]
            codeGen.emit("READ");
            codeGen.emit("STORE", info->memory_address);
        } else { // arr[x]
            save_address_to_reg(info, "b");
            codeGen.emit("READ"); // Wczytaj liczbę do ra
            codeGen.emit("RSTORE b"); // Zapisz ra do adresu wskazanego przez rb
        }
        symbolTable.markInitialized(info->name);
        delete info;
    }
    // Zapisz do r_a wartość value i wywołaj WRITE
    | WRITE value SEMICOLON {
        save_value_to_reg($2, "a");
        codeGen.emit("WRITE");
    }
    ;

// wywołanie procedury z listą argumentów np. fun(a, b, c)
proc_call:
    PIDENTIFIER LPAREN args RPAREN { // args są po kolei [a1, a2, a3,...]
        $$ = new ProcCall();
        $$->id = $1;
        $$->args = $3;
    }
    ;

args:
    args COMMA PIDENTIFIER{
        $$->arguments.push_back($3->pid);
    }
    | PIDENTIFIER {
        $$ = new Args();
        $$->arguments.push_back($1->pid);
    };

expression: // zapisuje wartość wyrażenia do r_a
    value PLUS value {
        save_value_to_reg($1, "b");
        save_value_to_reg($3, "a");
        codeGen.emit("ADD b");
    }
    | value MINUS value {
        save_value_to_reg($1, "b");
        save_value_to_reg($3, "a");
        codeGen.emit("SWP b");
        codeGen.emit("SUB b");
    }
    | value MULT value {
        if ($3 -> value == 0 && $3->var_info == nullptr) codeGen.emit("RST a");
        else if ($1 -> value == 0 && $1->var_info == nullptr) codeGen.emit("RST a");
        else if ($3 -> value == 2){
            save_value_to_reg($1, "a");
            codeGen.emit("SHL a");
        }
        else if ($1 -> value == 2){
            save_value_to_reg($3, "a");
            codeGen.emit("SHL a");
        }
        else if ($3 -> value == 1) save_value_to_reg($1, "a");
        else if ($1 -> value == 1) save_value_to_reg($3, "a");
        else{ //r_a = r_b*r_c metodą rosyjskich chłopów
            save_value_to_reg($1, "b");
            save_value_to_reg($3, "c");
            unsigned long long jumpLable = codeGen.getCurrentLine();
            codeGen.generateMult(jumpLable);
        }
    }
    | value DIV value {
        if ($3 -> value == 0 && $3->var_info == nullptr){
            codeGen.emit("RST a");
        }
        else if ($3 -> value == 1){
            save_value_to_reg($1, "a");
        }
        else if ($3 -> value == 2){
            save_value_to_reg($1, "a");
            codeGen.emit("SHR a");
        }
        else {
            // co z dzieleniem przez 0 jeśli value to nie NUM
            // SWP c    JZERO end_of_div    SWP c    a=b/c
            // generate_division_code w jednym rejestrze wynik w drugim reszta z dzielenia(modulo)
            save_value_to_reg($1, "b");
            save_value_to_reg($3, "c");
            codeGen.generateDiv();
            codeGen.emit("SWP h");
        }
    }
    | value MOD value {
        if ($3 -> value == 0 && $3->var_info == nullptr){
            codeGen.emit("RST a");
        }
        else if ($3 -> value == 1){
            codeGen.emit("RST a");
        }
        else{
            save_value_to_reg($1, "b");
            save_value_to_reg($3, "c");
            codeGen.generateDiv();
            codeGen.emit("SWP b");
        }
    }
    | value { save_value_to_reg($1, "a");}
    ;

//skaczemy jeśli fałsz (sprawdzamy warunek przeciwny)
condition:
    value EQ value { // (a-b)+(b-a)>0
        save_value_to_reg($1, "b");
        save_value_to_reg($3, "c");
        codeGen.generateIsEqual();
        $$ = &JPOS_lable;
    }
    | value NEQ value { // (a-b)+(b-a)=0
        save_value_to_reg($1, "b");
        save_value_to_reg($3, "c");
        codeGen.generateIsEqual();
        $$ = &JZERO_lable;
    }
    | value GT value { // a <= b -> a-b <= 0
        save_value_to_reg($3, "b");
        save_value_to_reg($1, "a");
        codeGen.emit("SUB b");
        $$ = &JZERO_lable;
    }
    | value LT value { // b >= a -> 0 >= a-b
        save_value_to_reg($1, "b");
        save_value_to_reg($3, "a");
        codeGen.emit("SUB b");
        $$ = &JZERO_lable;
    }
    | value GE value { // b < a -> a-b > 0
        save_value_to_reg($1, "b");
        save_value_to_reg($3, "a");
        codeGen.emit("SUB b");
        $$ = &JPOS_lable;
    }
    | value LE value { // a > b -> a-b > 0
        save_value_to_reg($3, "b");
        save_value_to_reg($1, "a");
        codeGen.emit("SUB b");
        $$ = &JPOS_lable;
    }
    ;

value: // zapisuje do ValueInfo wartość NUM albo wskaźnik do VariableInfo
    NUM {
        $$ = new ValueInfo();
        $$->value = $1;
        $$->var_info = nullptr;
    }
    | identifier{
        VariableInfo *info = $1;
        Symbol* sym = symbolTable.getSymbol(info->name);
        if(!sym->is_initialized && !sym->is_param) yyerror("Cannot access uninitialized variable");
        if(sym->is_O && !sym->is_initialized) yyerror("Cannot access uninitialized O variable");
        $$ = new ValueInfo();
        $$->var_info = info;
    }
    ;

// zapisuje w VariableInfo czy jest to zmienna x, tablica od indeksu tab[2], czy tablica od zmiennej tab[x] wraz z adresami i nazwą
identifier:
    PIDENTIFIER //x
    {
        Symbol* var = symbolTable.getSymbol($1->pid);
        if(var == nullptr) yyerror(("Variable \"" + std::string($1->pid) + "\" not declared").c_str());
        if(var->is_array == 1) yyerror(("Cannot access array \"" + std::string($1->pid) + "\" as variable").c_str());
        $$ = new VariableInfo();
        $$->sym = var;
        $$->name = $1->pid;
        $$->memory_address = var->memory_address;
        $$->is_param = var->is_param;
        $$->is_array_ref = false;
    }
    | PIDENTIFIER LBRACKET PIDENTIFIER RBRACKET //arr[x]
    {
        Symbol* arr = symbolTable.getSymbol($1->pid);
        if(arr == nullptr) yyerror(("Array \""+ std::string($1->pid) + "\" not declared").c_str());
        if(arr->is_array == 0) yyerror("Cannot access variable at index");

        Symbol* var = symbolTable.getSymbol($3->pid);
        if(var == nullptr) yyerror(("Variable \""+ std::string($3->pid) + "\" not declared").c_str());
        if(var->is_array == 1) yyerror("Cannot access array with another array");
        if(var->is_initialized == 0 && !var->is_param) yyerror("Cannot access array with an uninitialized variable");
        if(var->is_O == 1) yyerror("Cannot access O variable");

        $$ = new VariableInfo();
        $$->sym = arr;
        $$->ref = var;
        $$->name = $1->pid;
        $$->memory_address = arr->memory_address; // Adres bazowy tablicy
        $$->is_array_ref = true;
        $$->offset_or_addr = var->memory_address; // Adres zmiennej x
    }
    | PIDENTIFIER LBRACKET NUM RBRACKET //arr[5]
    {
        Symbol* sym = symbolTable.getSymbol($1->pid);
        if(sym == nullptr) yyerror("Array not declared");
        if(sym->is_array == 0) yyerror("Cannot access variable at index");
        unsigned long long start = sym->array_start;
        unsigned long long end = sym->array_end;
        
        if(!sym->is_T && ($3 < start || $3 > end)) yyerror("Array index out of bounds");
        if(sym->is_T) start = 0;
        
        $$ = new VariableInfo();
        $$->sym = sym;
        $$->name = $1->pid;
        $$->memory_address = sym->memory_address + ($3 - start);
        $$->is_array_ref = false;
    }
    ;

%%

/* Funkcja obsługi błędów */
void yyerror(char const *s) {
    std::cerr << "Error on line " << yylineno << ": " << s << std::endl;
    exit(-1);
}

void parse_code( std::vector< std::string > & code, FILE * data ) 
{
    codeGen.setCode(code);
    yyset_in( data );
    //extern int yydebug;
    //yydebug = 1; 
    yyparse();
    codeGen.backpatchAllCheck();
    symbolTable.leaveScope();
}