import React from "react";

const LABELS = {
  adicao: "Adição",
  subtracao: "Subtração",
  multiplicacao: "Multiplicação",
  divisao: "Divisão",
};

export default function PerformanceChart({ contents = [], recommendations = [] }) {
  const recMap = new Map(recommendations.map((r) => [r.content, Math.round((r.estimated_mastery || 0) * 100)]));

  const width = 640;
  const height = 240;
  const padLeft = 42;
  const padBottom = 36;
  const padTop = 20;
  const chartW = width - padLeft - 24;
  const chartH = height - padTop - padBottom;

  const items = contents.length > 0
    ? contents
    : [
        { content: "adicao", title: "Adição", score: 0 },
        { content: "subtracao", title: "Subtração", score: 0 },
        { content: "multiplicacao", title: "Multiplicação", score: 0 },
        { content: "divisao", title: "Divisão", score: 0 },
      ];

  const groupW = chartW / Math.max(1, items.length);
  const barW = Math.min(28, groupW * 0.28);

  return (
    <div className="card">
      <div className="card-header">
        <div>
          <h3 className="card-title">Evolução por Conteúdo</h3>
          <p className="muted" style={{ margin: 0 }}>
            Desempenho nas atividades vs. Probabilidade estimada pelo modelo
          </p>
        </div>
        <div style={{ display: "flex", gap: "0.85rem", fontSize: "0.8rem" }}>
          <span style={{ display: "inline-flex", alignItems: "center", gap: "0.35rem" }}>
            <span style={{ width: 12, height: 12, borderRadius: 3, background: "#2563eb", display: "inline-block" }} />
            Desempenho (%)
          </span>
          <span style={{ display: "inline-flex", alignItems: "center", gap: "0.35rem" }}>
            <span style={{ width: 12, height: 12, borderRadius: 3, background: "#059669", display: "inline-block" }} />
            Domínio Estimado (%)
          </span>
        </div>
      </div>

      <svg
        viewBox={`0 0 ${width} ${height}`}
        style={{ width: "100%", height: "auto", maxHeight: "260px", display: "block" }}
        role="img"
        aria-label="Gráfico comparativo de desempenho e domínio estimado por conteúdo"
      >
        {[0, 25, 50, 75, 100].map((tick) => {
          const y = padTop + chartH - (tick / 100) * chartH;
          return (
            <g key={tick}>
              <line x1={padLeft} y1={y} x2={width - 16} y2={y} stroke="#e2e8f0" strokeDasharray={tick === 75 ? "4 3" : undefined} />
              <text x={padLeft - 8} y={y + 4} textAnchor="end" fontSize="11" fill="#64748b">
                {tick}%
              </text>
            </g>
          );
        })}

        {items.map((item, idx) => {
          const scoreVal = Math.max(0, Math.min(100, Math.round(item.score || 0)));
          const masteryVal = recMap.get(item.content) ?? 0;
          const centerX = padLeft + groupW * idx + groupW / 2;

          const hScore = (scoreVal / 100) * chartH;
          const hMastery = (masteryVal / 100) * chartH;

          return (
            <g key={item.content || idx}>
              <rect
                x={centerX - barW - 3}
                y={padTop + chartH - hScore}
                width={barW}
                height={hScore}
                rx={4}
                fill="#2563eb"
              />
              <text
                x={centerX - barW / 2 - 3}
                y={padTop + chartH - hScore - 5}
                textAnchor="middle"
                fontSize="10"
                fontWeight="600"
                fill="#1e3a8a"
              >
                {scoreVal}%
              </text>

              <rect
                x={centerX + 3}
                y={padTop + chartH - hMastery}
                width={barW}
                height={hMastery}
                rx={4}
                fill="#059669"
              />
              <text
                x={centerX + barW / 2 + 3}
                y={padTop + chartH - hMastery - 5}
                textAnchor="middle"
                fontSize="10"
                fontWeight="600"
                fill="#065f46"
              >
                {masteryVal}%
              </text>

              <text
                x={centerX}
                y={height - 12}
                textAnchor="middle"
                fontSize="12"
                fontWeight="600"
                fill="#334155"
              >
                {LABELS[item.content] || item.title || item.content}
              </text>
            </g>
          );
        })}
      </svg>
    </div>
  );
}

