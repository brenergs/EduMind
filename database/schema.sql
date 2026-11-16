-- ============================================================
-- EduMind — Schema Relacional (PostgreSQL)
-- ============================================================

-- 1. Estudantes
CREATE TABLE IF NOT EXISTS estudantes (
    id              SERIAL PRIMARY KEY,
    nome            VARCHAR(150) NOT NULL,
    email           VARCHAR(255) NOT NULL UNIQUE,
    data_cadastro   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- 2. Professores
CREATE TABLE IF NOT EXISTS professores (
    id              SERIAL PRIMARY KEY,
    nome            VARCHAR(150) NOT NULL,
    email           VARCHAR(255) NOT NULL UNIQUE
);

-- 3. Conteúdos Educacionais
CREATE TABLE IF NOT EXISTS conteudos (
    id              SERIAL PRIMARY KEY,
    titulo          VARCHAR(120) NOT NULL UNIQUE,
    descricao       TEXT         NOT NULL,
    categoria       VARCHAR(80)  NOT NULL,
    nivel           INTEGER      NOT NULL CHECK (nivel >= 1)
);

-- 4. Grafo de Pré-Requisitos (conteudo_id depende de pre_requisito_id)
CREATE TABLE IF NOT EXISTS pre_requisitos (
    conteudo_id      INTEGER NOT NULL REFERENCES conteudos(id) ON DELETE CASCADE,
    pre_requisito_id INTEGER NOT NULL REFERENCES conteudos(id) ON DELETE CASCADE,
    PRIMARY KEY (conteudo_id, pre_requisito_id),
    CHECK (conteudo_id <> pre_requisito_id)
);

-- 5. Atividades / Exercícios
CREATE TABLE IF NOT EXISTS atividades (
    id              SERIAL PRIMARY KEY,
    conteudo_id     INTEGER     NOT NULL REFERENCES conteudos(id) ON DELETE CASCADE,
    titulo          VARCHAR(150) NOT NULL,
    descricao       TEXT        NOT NULL,
    dificuldade     INTEGER     NOT NULL CHECK (dificuldade BETWEEN 1 AND 5)
);

-- 6. Respostas dos Estudantes
CREATE TABLE IF NOT EXISTS respostas (
    id              SERIAL PRIMARY KEY,
    estudante_id    INTEGER     NOT NULL REFERENCES estudantes(id) ON DELETE CASCADE,
    atividade_id    INTEGER     NOT NULL REFERENCES atividades(id) ON DELETE CASCADE,
    resposta        TEXT        NOT NULL,
    resultado       BOOLEAN     NOT NULL, -- TRUE = correta, FALSE = incorreta
    tempo_resolucao INTEGER     CHECK (tempo_resolucao IS NULL OR tempo_resolucao >= 0), -- em segundos
    data_realizacao TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 7. Desempenho Consolidado por Estudante x Conteúdo
CREATE TABLE IF NOT EXISTS desempenho (
    id               SERIAL PRIMARY KEY,
    estudante_id     INTEGER          NOT NULL REFERENCES estudantes(id) ON DELETE CASCADE,
    conteudo_id      INTEGER          NOT NULL REFERENCES conteudos(id)  ON DELETE CASCADE,
    pontuacao        DOUBLE PRECISION NOT NULL CHECK (pontuacao BETWEEN 0.0 AND 100.0),
    data_atualizacao TIMESTAMPTZ      NOT NULL DEFAULT NOW(),
    UNIQUE (estudante_id, conteudo_id)
);

-- 8. Modelos Treinados e Versionamento
CREATE TABLE IF NOT EXISTS modelos (
    id               SERIAL PRIMARY KEY,
    algoritmo        VARCHAR(80)  NOT NULL,
    versao           VARCHAR(40)  NOT NULL UNIQUE,
    parametros       JSONB        NOT NULL, -- pesos W, bias b e parâmetros de normalização
    metricas         JSONB        NOT NULL, -- accuracy, precision, recall, f1, log_loss
    data_treinamento TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- 9. Recomendações Geradas
CREATE TABLE IF NOT EXISTS recomendacoes (
    id                     SERIAL PRIMARY KEY,
    estudante_id           INTEGER          NOT NULL REFERENCES estudantes(id) ON DELETE CASCADE,
    conteudo_id            INTEGER          NOT NULL REFERENCES conteudos(id)  ON DELETE CASCADE,
    justificativa          TEXT             NOT NULL,
    probabilidade_estimada DOUBLE PRECISION NOT NULL CHECK (probabilidade_estimada BETWEEN 0.0 AND 1.0),
    data_recomendacao      TIMESTAMPTZ      NOT NULL DEFAULT NOW()
);

-- Índices para consultas frequentes
CREATE INDEX IF NOT EXISTS idx_respostas_estudante     ON respostas(estudante_id, data_realizacao DESC);
CREATE INDEX IF NOT EXISTS idx_desempenho_estudante    ON desempenho(estudante_id);
CREATE INDEX IF NOT EXISTS idx_recomendacoes_estudante ON recomendacoes(estudante_id, data_recomendacao DESC);

-- ============================================================
-- Carga Inicial — Domínio Educacional Inicial (Seção 5.2 e 11.2)
-- ============================================================
INSERT INTO conteudos (id, titulo, descricao, categoria, nivel) VALUES
    (1, 'Adicao',        'Operacoes fundamentais de soma com numeros naturais.',             'Operacoes Matematicas', 1),
    (2, 'Subtracao',     'Operacoes fundamentais de subtracao com numeros naturais.',        'Operacoes Matematicas', 2),
    (3, 'Multiplicacao', 'Operacoes de multiplicacao e compreensao de fatores e produtos.',  'Operacoes Matematicas', 3),
    (4, 'Divisao',       'Operacoes de divisao exata e com resto entre numeros naturais.',   'Operacoes Matematicas', 4)
ON CONFLICT (titulo) DO NOTHING;

SELECT setval('conteudos_id_seq', COALESCE((SELECT MAX(id) FROM conteudos), 1));

-- Cadeia de pré-requisitos: Adição -> Subtração -> Multiplicação -> Divisão
INSERT INTO pre_requisitos (conteudo_id, pre_requisito_id) VALUES
    (2, 1), -- Subtração requer Adição
    (3, 2), -- Multiplicação requer Subtração
    (4, 3)  -- Divisão requer Multiplicação
ON CONFLICT DO NOTHING;

