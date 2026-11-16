# EduMind — Especificação de Machine Learning (`ai-engine`)

> **Status:** Fase 1 (Definição de variáveis, critérios de domínio e dataset sintético inicial)  
> **Algoritmo inicial:** Regressão Logística com Gradiente Descendente e Entropia Cruzada Binária

---

## 1. Objetivo do Modelo

Estimar a probabilidade $P(Y = 1 \mid X)$ de um estudante demonstrar domínio em um determinado conteúdo educacional (inicialmente `Adicao`, `Subtracao`, `Multiplicacao` e `Divisao`), a partir do seu histórico de desempenho e do desempenho em conteúdos pré-requisitos.

---

## 2. Mapeamento das Variáveis de Entrada (`X1`–`X6`)

| Variável | Coluna no CSV | Tipo | Escala / Unidade | Descrição e Cuidados Pedagógicos |
| :---: | :--- | :--- | :--- | :--- |
| `X1` | `desempenho_anterior` | `Double` | `0.0` a `100.0` | Média de desempenho em atividades anteriores do mesmo conteúdo. |
| `X2` | `respostas_corretas` | `Int` | $\ge 0$ | Quantidade acumulada de respostas corretas registradas no conteúdo. |
| `X3` | `tentativas` | `Int` | $\ge 1$ | Quantidade total de tentativas realizadas pelo estudante no conteúdo (`respostas_corretas <= tentativas` quando contabilizado por tentativa). |
| `X4` | `desempenho_prerequisitos` | `Double` | `0.0` a `100.0` | Desempenho médio consolidado nos conteúdos pré-requisitos diretos. Para conteúdos raiz sem pré-requisitos (ex.: `Adicao`), adota-se o valor neutro `100.0`. |
| `X5` | `desempenho_recente` | `Double` | `0.0` a `100.0` | Média de desempenho nas últimas $N$ atividades (padrão $N = 5$), refletindo o estágio atual de evolução do estudante. |
| `X6` | `tempo_medio_resolucao` | `Maybe Double` | Segundos ($\ge 0$) ou vazio | Tempo médio de resolução quando disponível e pedagogicamente relevante. |

### Cautela Pedagógica com `X6` (`tempo_medio_resolucao`)
- Rapidez na resposta **não implica domínio automaticamente** (pode indicar chute ou exercício trivial), assim como maior tempo gasto **não implica ausência de domínio** (pode indicar raciocínio cuidadoso ou leitura atenta).
- Valores ausentes em `X6` devem ser tratados na etapa de pré-processamento por imputação calculada **exclusivamente sobre o conjunto de treinamento** (ex.: mediana dos registros válidos de treino).

---

## 3. Variável de Saída (`Y`) e Critérios Pedagógicos de Domínio

| Rótulo (`dominio`) | Significado | Critério Pedagógico de Definição |
| :---: | :--- | :--- |
| `0` | Não demonstrou domínio | O estudante ainda necessita de reforço ou consolidação no conteúdo ou em seus pré-requisitos. |
| `1` | Demonstrou domínio | O estudante atingiu desempenho consistente de acordo com os critérios pedagógicos estabelecidos. |

### Diretrizes para Rotulagem
1. **Consistência, não evento isolado:** O rótulo `Y` nunca deve depender de uma única resposta isolada, mas sim de um conjunto mínimo de atividades/tentativas recentes.
2. **Critério inicial de referência para dados simulados:** Considera-se domínio demonstrado (`Y = 1`) quando há histórico mínimo suficiente (ex.: pelo menos 8–10 tentativas ou sequência consistente) com `desempenho_recente >= 75.0` e `desempenho_anterior >= 70.0`, sem lacunas críticas nos pré-requisitos (`desempenho_prerequisitos >= 70.0`).
3. **Evolução com especialistas:** Em produção com dados reais anonimizados, os critérios e rótulos deverão ser validados e revisados por professores e profissionais da educação.
4. **Não rotulagem punitiva:** Probabilidades estimadas baixas orientam reforço e revisão de pré-requisitos — jamais devem ser usadas para rotular incapacidade do estudante.

---

## 4. Regras Anti-Vazamento de Dados (*Data Leakage*)

Para garantir avaliação realista da capacidade de generalização do modelo:

1. **Divisão agrupada por identidade do estudante (`student_pseudo_id`):**
   - Ao particionar o conjunto de dados em **Treino**, **Validação** e **Teste**, todos os registros pertencentes a um mesmo `student_pseudo_id` devem ficar no mesmo subconjunto.
   - Um estudante presente no conjunto de Treino **nunca** deve aparecer nos conjuntos de Validação ou Teste.
2. **Pré-processamento e normalização ajustados apenas no Treino:**
   - Estatísticas de imputação (ex.: mediana de `tempo_medio_resolucao`) e parâmetros de normalização (`média`/`desvio` para Z-score ou `mín`/`máx` para Min-Max) devem ser computados **somente** sobre os exemplos de treinamento e armazenados em `ScalerParams`.
   - Os conjuntos de Validação, Teste e predições futuras apenas aplicam esses parâmetros já congelados.
3. **Pseudonimização obrigatória:**
   - Nenhum conjunto de treinamento ou CSV deve conter `nome`, `email` ou identificador pessoal direto — apenas `student_pseudo_id`.

---

## 5. Dataset Sintético Inicial (`ai-engine/datasets/sample.csv`)

- **Identificação explícita:** Todos os registros do arquivo inicial possuem a coluna `origem_dados = simulado`.
- **Cobertura inicial:** 10 estudantes simulados (`stu_001` a `stu_010`) distribuídos pelos 4 conteúdos iniciais (`Adicao`, `Subtracao`, `Multiplicacao`, `Divisao`), contemplando:
  - Casos positivos e negativos balanceados;
  - Progressão coerente com o grafo `Adicao -> Subtracao -> Multiplicacao -> Divisao`;
  - Valores ausentes propositais em `tempo_medio_resolucao` para testar a etapa de imputação;
  - Variações de tempo (estudantes rápidos com baixa acurácia e estudantes mais lentos com alto domínio) para evitar viés simplista sobre `X6`.

