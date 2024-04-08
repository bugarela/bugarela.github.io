------------------- MODULE ExerciciosAula ---------------------
EXTENDS FiniteSets, FiniteSetsExt, Integers, SequencesExt

\* 1. Dado um conjunto de números, retorne um conjunto do quadrado desses números.
quadrado(S) == { x*x: x \in S }

testeQuadrado == quadrado({1, 2, 3, 4})

quadradoFold(S) == FoldSet(LAMBDA i, acc: acc \union {i * i}, {}, S)

testeQuadradoFold == quadradoFold({1, 2, 3, 4})

\* 2. Dado um conjunto de números, retorne um conjunto apenas com os números pares.
pares(S) == { x \in S : x % 2 = 0}

testePares == pares({1, 2, 3, 4})

paresFold(S) == FoldSet(LAMBDA i, acc: IF i % 2 = 0 THEN acc \union {i} ELSE acc, {}, S)

testeParesFold == paresFold({1, 2, 3, 4})
============================================================
