import React from "react";

const CONTENT_LABELS = {
  adicao: "Adição",
  subtracao: "Subtração",
  multiplicacao: "Multiplicação",
  divisao: "Divisão",
};

const ACTION_CONFIG = {
  avancar: {
    label: "Avançar / Desafios",
    color: "#059669",
  },
  consolidacao: {
    label: "Consolidação",
    color: "#d97706",
  },
  reforco: {
    label: "Reforço Direcionado",
    color: "#2563eb",
  },
  revisar_pre_requisitos: {
    label: "Revisar Pré-requisitos",
    color: "#7c3aed",
  },
};

export default function RecommendationCard({
  item,
  onPractice,
  reviewStatus,
  onReviewChange,
}) {
  const pct = Math.round((item.estimated_mastery || 0) * 100);
  const cfg = ACTION_CONFIG[item.recommendation] || ACTION_CONFIG.consolidacao;
  const title = CONTENT_LABELS[item.content] || item.content;

  return (
    <article className="rec-card">
      <div>
        <div className="card-header" style={{ marginBottom: "0.5rem" }}>
          <h4 style={{ margin: 0, fontSize: "1rem" }}>{title}</h4>
          <span className={`badge badge-${item.recommendation}`}>{cfg.label}</span>
        </div>

        <div style={{ display: "flex", justifyContent: "space-between", fontSize: "0.84rem" }}>
          <span className="muted">Probabilidade estimada de domínio</span>
          <strong>{pct}%</strong>
        </div>

        <div className="progress-track" aria-label={`Domínio estimado de ${title}: ${pct}%`}>
          <div
            className="progress-fill"
            style={{ width: `${pct}%`, backgroundColor: cfg.color }}
          />
        </div>

        <p style={{ margin: "0.65rem 0 0", fontSize: "0.86rem", color: "#334155" }}>
          <strong>Justificativa:</strong> {item.reason}
        </p>

        {item.suggested_difficulty && (
          <p className="muted" style={{ margin: "0.35rem 0 0", fontSize: "0.8rem" }}>
            Dificuldade recomendada: Nível {item.suggested_difficulty} de 5
          </p>
        )}
      </div>

      <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap", alignItems: "center" }}>
        {onPractice && (
          <button
            type="button"
            className="btn btn-primary"
            style={{ flex: 1 }}
            onClick={() => onPractice(item.content)}
          >
            Praticar {title}
          </button>
        )}

        {onReviewChange && (
          <div style={{ display: "flex", gap: "0.35rem", width: "100%", marginTop: "0.25rem" }}>
            <button
              type="button"
              className={`btn ${reviewStatus === "aprovada" ? "btn-primary" : "btn-secondary"}`}
              style={{ flex: 1, fontSize: "0.78rem", padding: "0.4rem 0.6rem" }}
              onClick={() => onReviewChange(item.content, "aprovada")}
            >
              {reviewStatus === "aprovada" ? "✓ Aprovada pelo Professor" : "Aprovar"}
            </button>
            <button
              type="button"
              className={`btn ${reviewStatus === "ajustada" ? "btn-primary" : "btn-secondary"}`}
              style={{ flex: 1, fontSize: "0.78rem", padding: "0.4rem 0.6rem" }}
              onClick={() => onReviewChange(item.content, "ajustada")}
            >
              {reviewStatus === "ajustada" ? "✎ Em Revisão Docente" : "Sinalizar Ajuste"}
            </button>
          </div>
        )}
      </div>
    </article>
  );
}

