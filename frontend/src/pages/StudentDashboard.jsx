import React from "react";
import PerformanceChart from "../components/PerformanceChart.jsx";
import PrerequisiteGraph from "../components/PrerequisiteGraph.jsx";
import RecommendationCard from "../components/RecommendationCard.jsx";

export default function StudentDashboard({
  student,
  performance,
  recommendationsData,
  loading,
  onPracticeContent,
}) {
  if (loading && !performance) {
    return <div className="card">Carregando dados do estudante...</div>;
  }

  if (!student) {
    return (
      <div className="card">
        Nenhum estudante selecionado. Cadastre ou selecione um estudante no Painel do Professor.
      </div>
    );
  }

  const recommendations = recommendationsData?.recommendations || [];
  const modelVersion = recommendationsData?.model_version || "1.0";
  const contentsPerf = performance?.contents || [];
  const dominatedCount = recommendations.filter((r) => r.estimated_mastery >= 0.75).length;

  return (
    <div>
      <section className="grid-kpi">
        <div className="kpi-card">
          <div className="kpi-label">Estudante</div>
          <div className="kpi-value" style={{ fontSize: "1.2rem" }}>
            {student.nome}
          </div>
          <div className="muted" style={{ fontSize: "0.8rem" }}>
            {student.email}
          </div>
        </div>

        <div className="kpi-card">
          <div className="kpi-label">Desempenho Médio</div>
          <div className="kpi-value">{Math.round(performance?.overall_score || 0)}%</div>
          <div className="muted" style={{ fontSize: "0.8rem" }}>
            Nas atividades realizadas
          </div>
        </div>

        <div className="kpi-card">
          <div className="kpi-label">Atividades Registradas</div>
          <div className="kpi-value">{performance?.total_attempts || 0}</div>
          <div className="muted" style={{ fontSize: "0.8rem" }}>
            Histórico acumulado
          </div>
        </div>

        <div className="kpi-card">
          <div className="kpi-label">Conteúdos Consolidados</div>
          <div className="kpi-value">
            {dominatedCount} / {recommendations.length || 4}
          </div>
          <div className="muted" style={{ fontSize: "0.8rem" }}>
            Modelo ativo v{modelVersion}
          </div>
        </div>
      </section>

      <PrerequisiteGraph recommendations={recommendations} />

      <PerformanceChart contents={contentsPerf} recommendations={recommendations} />

      <section className="card">
        <div className="card-header">
          <div>
            <h3 className="card-title">Recomendações Personalizadas</h3>
            <p className="muted" style={{ margin: 0 }}>
              Ordenadas por prioridade pedagógica, pré-requisitos e estimativa de domínio (v{modelVersion})
            </p>
          </div>
        </div>

        {recommendations.length === 0 ? (
          <p className="muted">Nenhuma recomendação disponível ainda.</p>
        ) : (
          <div className="rec-list">
            {recommendations.map((item) => (
              <RecommendationCard
                key={item.content}
                item={item}
                onPractice={onPracticeContent}
              />
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

