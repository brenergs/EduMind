import React from "react";

export default function ActivityCard({ activity, contentTitle, selected, onSelect }) {
  return (
    <div
      className="rec-card"
      style={{
        borderColor: selected ? "var(--primary)" : "var(--border)",
        background: selected ? "var(--primary-soft)" : "var(--surface-alt)",
      }}
    >
      <div>
        <div className="card-header" style={{ marginBottom: "0.4rem" }}>
          <strong style={{ fontSize: "0.95rem" }}>{activity.titulo}</strong>
          <span className="badge badge-reforco">Nível {activity.dificuldade}/5</span>
        </div>
        {contentTitle && (
          <div className="muted" style={{ fontSize: "0.78rem", marginBottom: "0.3rem" }}>
            Conteúdo: {contentTitle}
          </div>
        )}
        <p style={{ margin: 0, fontSize: "0.88rem" }}>{activity.descricao}</p>
      </div>

      <button
        type="button"
        className={`btn ${selected ? "btn-primary" : "btn-secondary"}`}
        onClick={() => onSelect(activity)}
      >
        {selected ? "Atividade Selecionada" : "Iniciar Atividade"}
      </button>
    </div>
  );
}

