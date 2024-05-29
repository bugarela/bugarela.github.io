------------------- MODULE Semaforos -----------------------
EXTENDS Integers, FiniteSets
VARIABLE cores, proximo
CONSTANT SEMAFOROS

FicaVerde(s) ==  /\proximo = s
                /\ \A s2 \in SEMAFOROS : cores[s2] = "vermelho"
                /\cores' = [cores EXCEPT ![s] = "verde"]
                /\proximo' = (s + 1) % Cardinality(SEMAFOROS)

FicaAmarelo(s) == /\cores[s] = "verde"
                 /\cores' = [cores EXCEPT ![s] = "amarelo"]
                 /\UNCHANGED << proximo >>

FicaVermelho(s) == /\cores[s] = "amarelo"
              /\cores' = [cores EXCEPT ![s] = "vermelho"]
              /\UNCHANGED << proximo >>

Init == cores = [s \in SEMAFOROS |-> "vermelho"] /\proximo = 0

Next == \E s \in SEMAFOROS : FicaVerde(s) \/ FicaAmarelo(s) \/ FicaVermelho(s)

Inv == cores[2] /= "amarelo"

SemColisao == Cardinality({s \in SEMAFOROS : cores[s] = "verde"}) <= 1

Spec == Init /\[][Next]_<<cores, proximo>>
============================================================
