module semaforos {
  type Cor = Vermelho | Verde | Amarelo
  type Semaforo = int

  var cores: Semaforo -> Cor
  var proximo: Semaforo

  const SEMAFOROS: Set[Semaforo]

  action fica_verde(s: Semaforo): bool = all {
    proximo == s,
    SEMAFOROS.forall(s2 => cores.get(s2) == Vermelho),

    cores' = cores.set(s, Verde),
    proximo' = (s + 1) % SEMAFOROS.size(),
  }

  action fica_amarelo(s: Semaforo): bool = all {
    cores.get(s) == Verde,
    cores' = cores.set(s, Amarelo),
    proximo' = proximo,
  }

  action fica_vermelho(s: Semaforo): bool = all {
    cores.get(s) == Amarelo,
    cores' = cores.set(s, Vermelho),
    proximo' = proximo,
  }

  action init = all {
    cores' = SEMAFOROS.mapBy(_ => Vermelho),
    proximo' = 0,
  }

  action step = {
    nondet s = SEMAFOROS.oneOf()
    any { fica_verde(s), fica_amarelo(s), fica_vermelho(s) }
  }

  val inv = cores.get(2) != Amarelo
}

module semaforos_3 {
  import semaforos(SEMAFOROS=Set(0, 1, 2)).*
}
