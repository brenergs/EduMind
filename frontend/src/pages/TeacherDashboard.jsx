import React, { useState } from "react";
import RecommendationCard from "../components/RecommendationCard.jsx";
import {
  createActivity,
  createStudent,
  getTeacherReviews,
  saveTeacherReview,
  trainModel,
} from "../services/api.js";

export default function TeacherDashboard({
  students = [],
  selectedStudent,
  contents = [],
  performance,
  recommendationsData,
  modelStatus,
  onSelectStudent,
  onDataChanged,
}) {
  const [studentName, setStudentName] = useState("");
  const [studentEmail, setStudentEmail] = useState("");

  const [actContentId, setActContentId] = useState(contents[0]?.id || 1);
  const [actTitle, setActTitle] = useState("");
  const [actDesc, setActDesc] = useState("");
  const [actDiff, setActDiff] = useState(2);

  const [reviews, setReviews] = useState(() => getTeacherReviews());
  const [training, setTraining] = useState(false);
  const [notice, setNotice] = useState(null);

  const recommendations = recommendationsData?.recommendations || [];
  const supportNeeded = recommendations.filter(
    (r) => r.recommendation === "reforco" || r.recommendation === "revisar_pre_requisitos"
  );

  let parsedMetrics = {};
  try {
    parsedMetrics = modelStatus?.metrics ? JSON.parse(modelStatus.metrics) : {};
  } catch {
    parsedMetrics = {};
  }

  const handleCreateStudent = async (e) => {
    e.preventDefault();
    try {
      const created = await createStudent({ nome: studentName, email: studentEmail });
      setStudentName("");
      setStudentEmail("");
      setNotice({ type: "success", text: `Estudante "${created.nome}" cadastrado com ID ${created.id}.` });
      await onDataChanged(created.id);
    } catch (err) {
      setNotice({ type: "error", text: err.message });
    }
  };

  const handleCreateActivity = async (e) => {
    e.preventDefault();
    try {
      const created = await createActivity({
        conteudo_id: Number(actContentId),
        titulo: actTitle,
        descricao: actDesc,
        dificuldade: Number(actDiff),
      });
      setActTitle("");
      setActDesc("");
      setNotice({ type: "success", text: `Atividade "${created.titulo}" cadastrada com sucesso.` });
      await onDataChanged();
    } catch (err) {
      setNotice({ type: "error", text: err.message });
    }
  };

  const handleTrainModel = async () => {
    setTraining(true);
    try {
      const nextVersion = modelStatus?.model_version === "1.0" ? "1.1" : "1.0";
      const res = await trainModel({ version: nextVersion });
      setNotice({
        type: "success",
        text: `Modelo ${res.algorithm} v${res.model_version} treinado (perda treino: ${res.train_loss.toFixed(4)}, teste: ${res.test_loss.toFixed(4)}).`,
      });
      await onDataChanged();
    } catch (err) {
      setNotice({ type: "error", text: err.message });
    } finally {
      setTraining(false);
    }
  };

  const handleReviewChange = (contentSlug, status) => {
    if (!selectedStudent) return;
    const updated = saveTeacherReview(selectedStudent.id, contentSlug, status);
    setReviews({ ...updated });
  };

  return (
    <div>
      {notice && <div className={`alert alert-${notice.type}`}>{notice.text}</div>}

      <section className="grid-kpi">
        <div className="kpi-card">
          <div className="kpi-label">Estudantes Cadastrados</div>
          <div className="kpi-value">{students.length}</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-label">Conteúdos com Lacunas (Atual)</div>
          <div className="kpi-value">{supportNeeded.length}</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-label">Modelo de IA Ativo</div>
          <div className="kpi-value" style={{ fontSize: "1.2rem" }}>
            {modelStatus?.active ? `v${modelStatus.model_version}` : "Não treinado"}
          </div>
          <div className="muted" style={{ fontSize: "0.78rem" }}>
            {modelStatus?.algorithm || "RegressaoLogistica"}
          </div>
        </div>
        <div className="kpi-card">
          <div className="kpi-label">Supervisão Pedagógica</div>
          <div className="kpi-value" style={{ fontSize: "1.15rem" }}>
            Ativa
          </div>
          <div className="muted" style={{ fontSize: "0.78rem" }}>
            Apoio à decisão docente
          </div>
        </div>
      </section>

      <div className="card">
        <div className="card-header">
          <div>
            <h3 className="card-title">Acompanhamento Individual e Pré-requisitos (RF12)</h3>
            <p className="muted" style={{ margin: 0 }}>
              Selecione o estudante para revisar histórico, lacunas e recomendações
            </p>
          </div>
          <select
            className="student-select"
            value={selectedStudent?.id || ""}
            onChange={(e) => onSelectStudent(Number(e.target.value))}
          >
            {students.map((s) => (
              <option key={s.id} value={s.id}>
                {s.nome} ({s.email})
              </option>
            ))}
          </select>
        </div>

        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Conteúdo</th>
                <th>Pontuação</th>
                <th>Tentativas</th>
                <th>Acertos</th>
                <th>Tempo Médio</th>
              </tr>
            </thead>
            <tbody>
              {(performance?.contents || []).map((c) => (
                <tr key={c.content_id}>
                  <td>
                    <strong>{c.title}</strong>
                  </td>
                  <td>{Math.round(c.score)}%</td>
                  <td>{c.attempts}</td>
                  <td>{c.correct_answers}</td>
                  <td>
                    {c.average_resolution_time !== null && c.average_resolution_time !== undefined
                      ? `${Math.round(c.average_resolution_time)}s`
                      : "—"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <div className="card">
        <div className="card-header">
          <div>
            <h3 className="card-title">Supervisão e Revisão de Recomendações</h3>
            <p className="muted" style={{ margin: 0 }}>
              O EduMind atua como ferramenta de apoio pedagógico; professores revisam e validam as sugestões.
            </p>
          </div>
        </div>
        <div className="rec-list">
          {recommendations.map((item) => (
            <RecommendationCard
              key={item.content}
              item={item}
              reviewStatus={selectedStudent ? reviews[`${selectedStudent.id}:${item.content}`]?.status : undefined}
              onReviewChange={handleReviewChange}
            />
          ))}
        </div>
      </div>

      <div className="grid-2">
        <div className="card">
          <div className="card-header">
            <h3 className="card-title">Cadastrar Estudante (RF01)</h3>
          </div>
          <form onSubmit={handleCreateStudent} className="form-grid">
            <div className="form-field">
              <label htmlFor="student-name">Nome completo</label>
              <input
                id="student-name"
                className="input"
                value={studentName}
                onChange={(e) => setStudentName(e.target.value)}
                placeholder="Ex.: Mariana Souza"
                required
              />
            </div>
            <div className="form-field">
              <label htmlFor="student-email">E-mail institucional</label>
              <input
                id="student-email"
                className="input"
                type="email"
                value={studentEmail}
                onChange={(e) => setStudentEmail(e.target.value)}
                placeholder="mariana@escola.edu.br"
                required
              />
            </div>
            <button type="submit" className="btn btn-primary">
              Cadastrar Estudante
            </button>
          </form>
        </div>

        <div className="card">
          <div className="card-header">
            <h3 className="card-title">Cadastrar Atividade (RF03)</h3>
          </div>
          <form onSubmit={handleCreateActivity} className="form-grid">
            <div className="form-field">
              <label htmlFor="act-content">Conteúdo</label>
              <select
                id="act-content"
                className="select"
                value={actContentId}
                onChange={(e) => setActContentId(Number(e.target.value))}
              >
                {contents.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.titulo}
                  </option>
                ))}
              </select>
            </div>
            <div className="form-field">
              <label htmlFor="act-title">Título</label>
              <input
                id="act-title"
                className="input"
                value={actTitle}
                onChange={(e) => setActTitle(e.target.value)}
                placeholder="Ex.: Multiplicação por 9"
                required
              />
            </div>
            <div className="form-field">
              <label htmlFor="act-desc">Enunciado</label>
              <input
                id="act-desc"
                className="input"
                value={actDesc}
                onChange={(e) => setActDesc(e.target.value)}
                placeholder="Ex.: Calcule 9 x 6."
                required
              />
            </div>
            <div className="form-field">
              <label htmlFor="act-diff">Dificuldade (1 a 5)</label>
              <input
                id="act-diff"
                className="input"
                type="number"
                min="1"
                max="5"
                value={actDiff}
                onChange={(e) => setActDiff(Number(e.target.value))}
              />
            </div>
            <button type="submit" className="btn btn-primary">
              Cadastrar Atividade
            </button>
          </form>
        </div>
      </div>

      <div className="card">
        <div className="card-header">
          <div>
            <h3 className="card-title">Status e Atualização do Modelo de Machine Learning (RF11)</h3>
            <p className="muted" style={{ margin: 0 }}>
              Algoritmo: {modelStatus?.algorithm || "RegressaoLogistica"} • Versão:{" "}
              {modelStatus?.model_version || "nao_treinado"}
            </p>
          </div>
          <button
            type="button"
            className="btn btn-primary"
            onClick={handleTrainModel}
            disabled={training}
          >
            {training ? "Treinando..." : "Solicitar Retreinamento"}
          </button>
        </div>

        <div className="grid-kpi" style={{ marginBottom: 0 }}>
          <div className="kpi-card">
            <div className="kpi-label">Perda de Treino (Log Loss)</div>
            <div className="kpi-value" style={{ fontSize: "1.2rem" }}>
              {typeof parsedMetrics.train_loss === "number" ? parsedMetrics.train_loss.toFixed(4) : "—"}
            </div>
          </div>
          <div className="kpi-card">
            <div className="kpi-label">Perda de Validação</div>
            <div className="kpi-value" style={{ fontSize: "1.2rem" }}>
              {typeof parsedMetrics.validation_loss === "number"
                ? parsedMetrics.validation_loss.toFixed(4)
                : "—"}
            </div>
          </div>
          <div className="kpi-card">
            <div className="kpi-label">Perda de Teste</div>
            <div className="kpi-value" style={{ fontSize: "1.2rem" }}>
              {typeof parsedMetrics.test_loss === "number" ? parsedMetrics.test_loss.toFixed(4) : "—"}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

