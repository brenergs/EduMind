import React from "react";

const ORDER = ["adicao", "subtracao", "multiplicacao", "divisao"];
const LABELS = {
  adicao: "Adição",
  subtracao: "Subtração",
  multiplicacao: "Multiplicação",
  divisao: "Divisão",
};

export default function PrerequisiteGraph({ recommendations = [] }) {
  const recMap = new Map(recommendations.map((r) => [r.content, r]));

  return (
    <div className="card">
      <div className="card-header">
        <div>
          <h3 className="card-title">Grafo de Pré-requisitos Pedagógicos</h3>
          <p className="muted" style={{ margin: 0 }}>
            Sequência direcionada de aprendizagem (Adição → Subtração → Multiplicação → Divisão)
          </p>
        </div>
      </div>

      <div className="prereq-flow">
        {ORDER.map((slug, index) => {
          const item = recMap.get(slug);
          const pct = item ? Math.round(item.estimated_mastery * 100) : 0;
          let nodeClass = "prereq-node";
          let statusLabel = "Sem registros";

          if (item) {
            if (item.estimated_mastery >= 0.75) {
              nodeClass += " mastered";
              statusLabel = "Consolidado";
            } else if (item.estimated_mastery >= 0.5) {
              nodeClass += " building";
              statusLabel = "Em consolidação";
            } else {
              nodeClass += " support";
              statusLabel =
                item.recommendation === "revisar_pre_requisitos"
                  ? "Aguardando pré-requisito"
                  : "Apoio recomendado";
            }
          }

          return (
            <React.Fragment key={slug}>
              <div className={nodeClass}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                  <strong>{LABELS[slug]}</strong>
                  <span style={{ fontSize: "0.84rem", fontWeight: 700 }}>{pct}%</span>
                </div>
                <div className="muted" style={{ fontSize: "0.78rem", marginTop: "0.25rem" }}>
                  {statusLabel}
                </div>
              </div>
              {index < ORDER.length - 1 && (
                <span className="prereq-arrow" aria-hidden="true">
                  →
                </span>
              )}
            </React.Fragment>
          );
        })}
      </div>
    </div>
  );
}

