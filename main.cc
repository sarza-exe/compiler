#include <iostream>
#include <vector>
#include <string>
#include <cstdio>

#include "symbolTable.hh"

using namespace std;

extern void parse_code(vector<string>& program, FILE* data);

/// @brief łączy kompilator w całość. Czyta kod, wywołuje parser i zapisuje kod maszyny wirtualnej
/// @param argv [1] plik wejściowy kodu, [2] plik wyjściowy do zapisania kodu vm
int main(int argc, char const* argv[]) {
    vector<string> program;
    FILE* input = nullptr;
    FILE* output = nullptr;

    if (argc != 3) {
        cerr << "Sposób użycia: kompilator plik_wejściowy plik_wyjściowy\n";
        return 1;
    }

    input = fopen(argv[1], "r");
    if (!input) {
        cerr << "Błąd: Nie można otworzyć pliku wejściowego " << argv[1] << "\n";
        return 1;
    }

    output = fopen(argv[2], "w");
    if (!output) {
        cerr << "Błąd: Nie można otworzyć pliku wyjściowego " << argv[2] << "\n";
        fclose(input);
        return 1;
    }

    parse_code(program, input);

    for (const auto& line : program) {
        fprintf(output, "%s\n", line.c_str());
    }

    fclose(input);
    fclose(output);

    return 0;
}
