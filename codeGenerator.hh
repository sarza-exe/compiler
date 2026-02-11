#pragma once
#include <vector>
#include <string>
#include <unordered_map>
#include <iostream>

struct Fixup {
    int instr_index; // indeks instrukcji w code (pozycja do uzupełnienia)
    int lable; // id etykiety, którą ma wskazywać
    std::string op; // instrukcja np JZERO
    };

class CodeGenerator {
    std::vector<std::string>* code = nullptr;

    int next_lable_id; // generuje nowe id etykiet
    std::unordered_map<int,int> lable_address; // lable_id -> code index (adres)
    std::vector<Fixup> pending_fixups; // zapisuje skoki do backpatchowania
    std::vector<int> lable_stack; // stack na lable skoków

public:

    CodeGenerator(){
        next_lable_id = 0;
        lable_address.clear();
        pending_fixups.clear();
    }

    /// @brief ustawia referencje kodu i emituje lable skoku do main
    /// @param codeRef referencja do kodu z programu main
    void setCode(std::vector<std::string> & codeRef) {
        code = &codeRef;
        int L_end  = newLable();
        pushLable(L_end);
        emitLable(L_end, "JUMP");
    }
    
    /// @brief dodaje instrukcje do wektora kodu
    /// @param instruction 
    void emit(std::string instruction) {
        code->push_back(instruction);
    }
    
    /// @brief emituje instrukcje z argumentem np. LOAD 4
    /// @param instruction 
    /// @param arg 
    void emit(std::string instruction, unsigned long long arg){
        code->push_back(instruction + " " + std::to_string(arg));
    }

    /// @brief emituje instrukcje z argumentem i komentarzem na końcu, który jest ignorowanym przez maszynę wirtualną
    /// @param instruction 
    /// @param arg 
    /// @param comment 
    void emit(std::string instruction, unsigned long long arg, std::string comment){
        code->push_back(instruction + " " + std::to_string(arg) + " #" + comment);
    }

    /// @brief Tworzy nową etykietę
    /// @return id nowej etykiety
    int newLable() {
        return next_lable_id++;
    }

    /// @brief dodaje lable skoku na stos
    /// @param L wartość lable zwrócony przez newLable
    void pushLable(int L) { 
        lable_stack.push_back(L); 
    }

    /// @brief 
    /// @return zwraca lable z góry stosu 
    int popLable() { 
        if (lable_stack.empty()) {
            std::cerr << "Internal error: popLable on empty stack\n";
            throw std::runtime_error("popLable on empty stack");
        }
        int v = lable_stack.back();
        lable_stack.pop_back();
        return v;
    }

    /// @brief Emituje string j_lable i dopisuje do pending_fixups. Jeśli poprzez defineLable lable ma już numer linii skoku to go dopisuje.
    /// @param lable numer lable z newLable
    /// @param j_lable instrukcja skoku np. JZERO
    void emitLable(int lable, std::string j_lable) {
        auto it = lable_address.find(lable);
        if (it != lable_address.end()) { // lable already known -> emit direct
            code->push_back(j_lable + " " + std::to_string(it->second));
        } else {
            int idx = (int)code->size();
            code->push_back(j_lable);  // placeholder
            pending_fixups.push_back({idx, lable, j_lable});
        }
    }

    /// @brief Definiuje etykietę (oznacza miejsce aktualnym numerem linii kodu) i backpatchuje
    /// @param lable instrukcja skoku do zdefiniowania
    void defineLable(int lable) {
        int addr = (int)code->size();
        if (lable_address.find(lable) != lable_address.end()) {
            std::cerr << "Lable " << lable << " already defined\n";
            return;
        }
        lable_address[lable] = addr;

        // backpatchuj wszystkie pending_fixups, które celują w ten lable
        for (auto it = pending_fixups.begin(); it != pending_fixups.end(); ) {
            if (it->lable == lable) {
                std::string new_instr = it->op + " " + std::to_string(addr);
                code->at(it->instr_index) = new_instr;
                it = pending_fixups.erase(it);
            } else {
                ++it;
            }
        }
    }

    /// @brief Na końcu parsowania upewnia się, że wszystkie etykiety skoku zdefiniowano
    void backpatchAllCheck() {
        if (!pending_fixups.empty()) {
            for (const auto &f : pending_fixups) {
                throw std::domain_error("Unresolved jump to lable " + std::to_string(f.lable) + " at instr " + std::to_string(f.instr_index));
            }
        }
    }

    /// @brief generuje w danym rejestrze stałą wartość n
    /// @param reg rejestr ('a','b',..., 'h')
    /// @param n wartość do wygenerowania w rejestrze
    void generateConstant(std::string reg, unsigned long long n){
        emit("RST " + reg); //0
        if(n == 0) return;
        emit("INC " + reg); // 1
        if(n == 1) return;

        // oblicza odwróconą wartość binarną n w stringu
        std::string n_bin = "";
        while(n > 0){
            int bit = n%2;
            n_bin.push_back('0' + bit);
            n /= 2;
        }
        
        // idziemy po n_bin od lewej do prawej, bo jest odwrócony
        for(int i = ((int)n_bin.length()-2); i >= 0; i--)
        {
            emit("SHL " + reg); // *=2
            if(n_bin[i] == '1') emit("INC " + reg);
        }
    }

    /// @brief 
    /// @return aktualny numer lini kodu 
    unsigned long long getCurrentLine()
    {
        return (unsigned long long)code->size();
    }

    /// @brief generuje kod do podzielenia wartości rejestru b przez c. W rejestrze h przechowywana jest wartość rb div rc, a w rb reszta z dzielenia
    void generateDiv(){
        int L_zero_div = newLable();
        emit("RST a");
        emit("ADD c");
        emitLable(L_zero_div, "JZERO");

        emit("RST d"); emit("INC d"); // rd = 1
        emit("RST h"); 

        int L_start = newLable();
        defineLable(L_start);
        emit("RST a #Starting DIV"); //start
        emit("ADD c"); emit("SHL a"); emit("SUB b"); //ra = 2*rc-rb
        int L_loop_two = newLable();
        emitLable(L_loop_two, "JPOS"); //if 2*rc-rb > 0 jump to loop_two

        emit("SHL c"); //rc = 2*rc
        emit("SHL d"); //rd = 2*rd
        emitLable(L_start, "JUMP");

        defineLable(L_loop_two);
        emit("RST a"); //loop_two
        emit("ADD d"); //ra = rd
        int L_return = newLable();
        emitLable(L_return, "JZERO"); //if(rd == 0) jump to the end

        emit("RST a"); emit("ADD c"); emit("SUB b"); // ra = rc-rb
        int L_VI = newLable();
        emitLable(L_VI, "JPOS"); // if(rc-rb > 0) jump to VI

        emit("SWP b"); emit("SUB c"); emit("SWP b"); //rb = rb-rc
        emit("SWP h"); emit("ADD d"); emit("SWP h"); //rh = rh+rd
 
        defineLable(L_VI);
        emit("SHR c"); //VI
        emit("SHR d");
        emitLable(L_loop_two, "JUMP");
        emitLable(L_return, "JUMP");
        defineLable(L_zero_div);
        emit("RST b");
        emit("RST h");
        defineLable(L_return);
        //rh jako iloraz, a rb to reszta
    }

    /// @brief generuje kod mnożenia ra = rb * rc.
    /// @param jump_lable aktualny numer lini by statycznie uzupełnić instrukcje skoku (zaprogramowane przed generowaniem skoków i backpatchingiem)
    void generateMult(unsigned long long jump_lable ){
        emit("RST a #MULT START"); //ra = 0
        emit("SWP d"); //ra <-> rd
        emit("RST a"); //ra = 0
        emit("ADD b"); //ra += b
        emit("SHR a"); //ra = ra/2
        emit("SHL a"); //ra = ra*2
        emit("SWP b"); //ra <-> rb
        emit("SUB b"); //ra = ra-rb
        emit("JZERO", jump_lable+12); // jeśli rb%2==0 jump
        emit("SWP d");
        emit("ADD c");
        emit("SWP d");
        emit("SWP d");
        emit("SHL c");
        emit("SHR b");
        emit("SWP b");
        emit("JZERO", jump_lable+19); // jeśli rb==0 end
        emit("SWP b");
        emit("JUMP", jump_lable+1); // while(rb)
        emit("SWP b #MULT END");
    }

    /// @brief generuje kod ra = (rb - rc) + (rc - rb) do sprawdzania czy rc == rb instrukcją JPOS
    void generateIsEqual(){
        emit("RST a");
        emit("ADD b");
        emit("SUB c"); // ra = val1 - val2
        emit("SWP d"); // schowaj wynik w rd
    
        emit("RST a");
        emit("ADD c");
        emit("SUB b"); // ra = val2 - val1
        
        emit("ADD d"); // ra = (val2-val1) + (val1-val2)
    }

};