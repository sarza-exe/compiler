%option noyywrap
%{
    #include <string.h>
    #include "parser.hh"  
%}

%option yylineno

%%
[ \t\r]+                ;
"#".*                   ;
\n                      ;

":="                    { return ASSIGN; }
"!="                    { return NEQ; }
"<="                    { return LE; }
">="                    { return GE; }

";"                     { return SEMICOLON; }
","                     { return COMMA; }
":"                     { return COLON; }
"("                     { return LPAREN; }
")"                     { return RPAREN; }
"["                     { return LBRACKET; }
"]"                     { return RBRACKET; }

"+"                     { return PLUS; }
"-"                     { return MINUS; }
"*"                     { return MULT; }
"/"                     { return DIV; }
"%"                     { return MOD; }

"="                     { return EQ; }
"<"                     { return LT; }
">"                     { return GT; }

"PROCEDURE"             { return PROCEDURE; }
"IS"                    { return IS; }
"IN"                    { return IN; }
"END"                   { return END; }
"PROGRAM"               { return PROGRAM; }

"IF"                    { return IF; }
"THEN"                  { return THEN; }
"ELSE"                  { return ELSE; }
"ENDIF"                 { return ENDIF; }

"WHILE"                 { return WHILE; }
"DO"                    { return DO; }
"ENDWHILE"              { return ENDWHILE; }

"REPEAT"                { return REPEAT; }
"UNTIL"                 { return UNTIL; }

"FOR"                   { return FOR; }
"FROM"                  { return FROM; }
"TO"                    { return TO; }
"DOWNTO"                { return DOWNTO; }
"ENDFOR"                { return ENDFOR; }

"READ"                  { return READ; }
"WRITE"                 { return WRITE; }

"T"                     { return T; }
"I"                     { return I_CONST; }
"O"                     { return O_VAR; }

[0-9]+                  {
                          yylval.num = strtoll(yytext, NULL, 10);
                          return NUM;
                        }


[_a-z]+                 {        
                          Identifier *id = new Identifier;
                          id->pid = strdup(yytext);
                          id->num = yylineno;
                          yylval.id = id;
                          return PIDENTIFIER;
                        }

.                       { fprintf(stderr, "Unrecognized character '%s'\n", yytext); return ERROR; }

%%