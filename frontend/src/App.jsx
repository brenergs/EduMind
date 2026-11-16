import React, { useCallback, useEffect, useRef, useState } from "react";
import ActivityRunner from "./pages/ActivityRunner.jsx";
import StudentDashboard from "./pages/StudentDashboard.jsx";
import TeacherDashboard from "./pages/TeacherDashboard.jsx";
import {
  getApiConnectionMode,
  getModelStatus,
  getStudentPerformance,
  getStudentRecommendations,
  listContents,
  listStudents,
} from "./services/api.js";

export default function App() {
  const [activeTab, setActiveTab] = useState("student");
  const [practiceContentSlug, setPracticeContentSlug] = useState("todos");

  const [students, setStudents] = useState([]);
  const [selectedStudentId, setSelectedStudentId] = useState(null);
  const selectedStudentIdRef = useRef(null);
  selectedStudentIdRef.current = selectedStudentId;

  const [contents, setContents] = useState([]);
  const [performance, setPerformance] = useState(null);
  const [recommendationsData, setRecommendationsData] = useState(null);
  const [modelStatus, setModelStatus] = useState(null);
  const [loading, setLoading] = useState(true);
  const [apiMode, setApiMode] = useState("checking");

  const refreshGlobalData = useCallback(async (overrideStudentId = null) => {
    setLoading(true);
    try {
      const [studs, conts, modStatus] = await Promise.all([
        listStudents(),
        listContents(),
        getModelStatus(),
      ]);
      setStudents(studs);
      setContents(conts);
      setModelStatus(modStatus);

      const targetId = overrideStudentId ?? selectedStudentIdRef.current ?? studs[0]?.id ?? null;
      if (targetId !== null) {
        setSelectedStudentId(targetId);
        const [perf, recs] = await Promise.all([
          getStudentPerformance(targetId),
          getStudentRecommendations(targetId),
        ]);
        setPerformance(perf);
        setRecommendationsData(recs);
      }
      setApiMode(getApiConnectionMode());
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refreshGlobalData();
  }, [refreshGlobalData]);

  const handleSelectStudent = async (id) => {
    setSelectedStudentId(id);
    setLoading(true);
    try {
      const [perf, recs] = await Promise.all([
        getStudentPerformance(id),
        getStudentRecommendations(id),
      ]);
      setPerformance(perf);
      setRecommendationsData(recs);
      setApiMode(getApiConnectionMode());
    } finally {
      setLoading(false);
    }
  };

  const handlePracticeContent = (slug) => {
    setPracticeContentSlug(slug);
    setActiveTab("activities");
  };

  const selectedStudent = students.find((s) => s.id === selectedStudentId) || null;

  return (
    <div className="app-shell">
      <header className="topbar">
        <div className="brand">
          <div className="brand-logo">E</div>
          <div>
            <h1>EduMind</h1>
            <p>Recomendação e Personalização da Aprendizagem</p>
          </div>
        </div>

        <nav className="nav-tabs" aria-label="Navegação principal">
          <button
            type="button"
            className={`nav-tab ${activeTab === "student" ? "active" : ""}`}
            onClick={() => setActiveTab("student")}
          >
            Painel do Estudante
          </button>
          <button
            type="button"
            className={`nav-tab ${activeTab === "activities" ? "active" : ""}`}
            onClick={() => setActiveTab("activities")}
          >
            Praticar Atividades
          </button>
          <button
            type="button"
            className={`nav-tab ${activeTab === "teacher" ? "active" : ""}`}
            onClick={() => setActiveTab("teacher")}
          >
            Painel do Professor
          </button>
        </nav>

        <div className="topbar-controls">
          {students.length > 0 && (
            <select
              aria-label="Selecionar estudante ativo"
              className="student-select"
              value={selectedStudentId ?? ""}
              onChange={(e) => handleSelectStudent(Number(e.target.value))}
            >
              {students.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.nome}
                </option>
              ))}
            </select>
          )}
          <span className={`mode-pill ${apiMode === "online" ? "online" : "offline"}`}>
            {apiMode === "online" ? "API Haskell Online" : "Modo Simulado Local"}
          </span>
        </div>
      </header>

      <main className="main-content">
        {activeTab === "student" && (
          <StudentDashboard
            student={selectedStudent}
            performance={performance}
            recommendationsData={recommendationsData}
            loading={loading}
            onPracticeContent={handlePracticeContent}
          />
        )}

        {activeTab === "activities" && (
          <ActivityRunner
            student={selectedStudent}
            contents={contents}
            initialContentSlug={practiceContentSlug}
            onAnswerSubmitted={() => refreshGlobalData(selectedStudentId)}
          />
        )}

        {activeTab === "teacher" && (
          <TeacherDashboard
            students={students}
            selectedStudent={selectedStudent}
            contents={contents}
            performance={performance}
            recommendationsData={recommendationsData}
            modelStatus={modelStatus}
            onSelectStudent={handleSelectStudent}
            onDataChanged={refreshGlobalData}
          />
        )}
      </main>

      <footer className="footer">
        EduMind v1.0 • Ferramenta de apoio pedagógico com Machine Learning em Haskell e supervisão docente.
      </footer>
    </div>
  );
}
