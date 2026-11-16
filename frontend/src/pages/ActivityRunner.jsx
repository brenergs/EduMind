import React, { useEffect, useMemo, useState } from "react";
import ActivityCard from "../components/ActivityCard.jsx";
import { registerAnswer } from "../services/api.js";

function extractExpectedAnswer(description) {
  if (!description) return null;
  const match = description.match(/(\d+(?:[.,]\d+)?)\s*([+\-*/xX×÷])\s*(\d+(?:[.,]\d+)?)/);
  if (!match) return null;

  const a = Number(match[1].replace(",", "."));
  const op = match[2];
  const b = Number(match[3].replace(",", "."));

  if (op === "+") return a + b;
  if (op === "-") return a - b;
  if (op === "*" || op.toLowerCase() === "x" || op === "×") return a * b;
  if (op === "/" || op === "÷") return b !== 0 ? a / b : null;
  return null;
}

export default function ActivityRunner({
  student,
  contents = [],
  initialContentSlug = "todos",
  onAnswerSubmitted,
}) {
  const [selectedSlug, setSelectedSlug] = useState(initialContentSlug);
  const [selectedActivity, setSelectedActivity] = useState(null);
  const [answerInput, setAnswerInput] = useState("");
  const [manualCorrect, setManualCorrect] = useState(true);
  const [attempts, setAttempts] = useState(1);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const [submitting, setSubmitting] = useState(false);
  const [feedback, setFeedback] = useState(null);

  useEffect(() => {
    setSelectedSlug(initialContentSlug || "todos");
  }, [initialContentSlug]);

  const flatActivities = useMemo(() => {
    return contents.flatMap((c) =>
      (c.atividades || []).map((a) => ({
        ...a,
        contentSlug: c.slug,
        contentTitle: c.titulo,
      }))
    );
  }, [contents]);

  const visibleActivities = useMemo(() => {
    if (selectedSlug === "todos") return flatActivities;
    return flatActivities.filter((a) => a.contentSlug === selectedSlug);
  }, [flatActivities, selectedSlug]);

  useEffect(() => {
    if (!selectedActivity) return undefined;
    const timer = setInterval(() => {
      setElapsedSeconds((prev) => prev + 1);
    }, 1000);
    return () => clearInterval(timer);
  }, [selectedActivity]);

  const handleSelectActivity = (act) => {
    setSelectedActivity(act);
    setAnswerInput("");
    setAttempts(1);
    setElapsedSeconds(0);
    setFeedback(null);
    setManualCorrect(true);
  };

  const expectedValue = useMemo(
    () => extractExpectedAnswer(selectedActivity?.descricao),
    [selectedActivity]
  );

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!student || !selectedActivity) return;

    let isCorrect = manualCorrect;
    if (expectedValue !== null) {
      const parsed = Number(answerInput.trim().replace(",", "."));
      if (Number.isNaN(parsed)) {
        setFeedback({ type: "error", text: "Digite um valor numérico válido para responder." });
        return;
      }
      isCorrect = Math.abs(parsed - expectedValue) < 1e-6;
    }

    setSubmitting(true);
    try {
      const result = await registerAnswer({
        student_id: student.id,
        activity_id: selectedActivity.id,
        correct: isCorrect,
        attempts,
        resolution_time: Math.max(1, elapsedSeconds),
        answer: answerInput.trim() || (isCorrect ? "correta" : "incorreta"),
      });

      if (isCorrect) {
        setFeedback({
          type: "success",
          text: `Resposta registrada como correta em ${Math.max(1, elapsedSeconds)}s! Desempenho atualizado no conteúdo: ${Math.round(result.updated_score)}%.`,
        });
      } else {
        setFeedback({
          type: "info",
          text: `Resposta registrada (pontuação atualizada no conteúdo: ${Math.round(result.updated_score)}%). Você pode tentar novamente ou revisar o conteúdo anterior.`,
        });
        setAttempts((prev) => prev + 1);
      }

      if (onAnswerSubmitted) {
        await onAnswerSubmitted();
      }
    } catch (err) {
      setFeedback({ type: "error", text: err.message || "Falha ao registrar resposta." });
    } finally {
      setSubmitting(false);
    }
  };

  if (!student) {
    return <div className="card">Selecione um estudante no topo para realizar atividades.</div>;
  }

  return (
    <div>
      <div className="card">
        <div className="card-header">
          <div>
            <h3 className="card-title">Praticar Atividades</h3>
            <p className="muted" style={{ margin: 0 }}>
              Estudante ativo: <strong>{student.nome}</strong>
            </p>
          </div>
          <div className="nav-tabs">
            {[
              { slug: "todos", label: "Todos" },
              { slug: "adicao", label: "Adição" },
              { slug: "subtracao", label: "Subtração" },
              { slug: "multiplicacao", label: "Multiplicação" },
              { slug: "divisao", label: "Divisão" },
            ].map((tab) => (
              <button
                key={tab.slug}
                type="button"
                className={`nav-tab ${selectedSlug === tab.slug ? "active" : ""}`}
                onClick={() => setSelectedSlug(tab.slug)}
              >
                {tab.label}
              </button>
            ))}
          </div>
        </div>

        <div className="rec-list">
          {visibleActivities.map((act) => (
            <ActivityCard
              key={act.id}
              activity={act}
              contentTitle={act.contentTitle}
              selected={selectedActivity?.id === act.id}
              onSelect={handleSelectActivity}
            />
          ))}
        </div>
      </div>

      {selectedActivity && (
        <div className="card">
          <div className="card-header">
            <div>
              <h3 className="card-title">{selectedActivity.titulo}</h3>
              <p className="muted" style={{ margin: 0 }}>
                {selectedActivity.contentTitle} • Dificuldade {selectedActivity.dificuldade}/5
              </p>
            </div>
            <div style={{ display: "flex", gap: "0.75rem", fontSize: "0.86rem" }}>
              <span className="badge badge-consolidacao">Tentativa #{attempts}</span>
              <span className="badge badge-reforco">Tempo: {elapsedSeconds}s</span>
            </div>
          </div>

          <p style={{ fontSize: "1.1rem", fontWeight: 600, marginBottom: "1rem" }}>
            {selectedActivity.descricao}
          </p>

          {feedback && (
            <div className={`alert alert-${feedback.type}`}>{feedback.text}</div>
          )}

          <form onSubmit={handleSubmit} className="form-grid" style={{ maxWidth: "420px" }}>
            <div className="form-field">
              <label htmlFor="answer-input">Sua resposta</label>
              <input
                id="answer-input"
                className="input"
                type="text"
                placeholder="Digite o resultado..."
                value={answerInput}
                onChange={(e) => setAnswerInput(e.target.value)}
                required
              />
            </div>

            {expectedValue === null && (
              <div className="form-field">
                <label htmlFor="manual-correct-select">Resultado (atividade aberta)</label>
                <select
                  id="manual-correct-select"
                  className="select"
                  value={manualCorrect ? "true" : "false"}
                  onChange={(e) => setManualCorrect(e.target.value === "true")}
                >
                  <option value="true">Resposta correta</option>
                  <option value="false">Precisa de revisão</option>
                </select>
              </div>
            )}

            <button type="submit" className="btn btn-primary" disabled={submitting}>
              {submitting ? "Enviando..." : "Enviar Resposta"}
            </button>
          </form>
        </div>
      )}
    </div>
  );
}

