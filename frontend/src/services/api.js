const STORAGE_KEY = "edumind_demo_state_v1";

let apiMode = "checking"; // "online" | "offline"

export function getApiConnectionMode() {
  return apiMode;
}

const DEFAULT_CONTENTS = [
  {
    id: 1,
    titulo: "Adicao",
    slug: "adicao",
    descricao: "Operacoes fundamentais de soma com numeros naturais.",
    categoria: "Operacoes Matematicas",
    nivel: 1,
    pre_requisitos: [],
  },
  {
    id: 2,
    titulo: "Subtracao",
    slug: "subtracao",
    descricao: "Operacoes fundamentais de subtracao com numeros naturais.",
    categoria: "Operacoes Matematicas",
    nivel: 2,
    pre_requisitos: [1],
  },
  {
    id: 3,
    titulo: "Multiplicacao",
    slug: "multiplicacao",
    descricao: "Operacoes de multiplicacao e compreensao de fatores e produtos.",
    categoria: "Operacoes Matematicas",
    nivel: 3,
    pre_requisitos: [2],
  },
  {
    id: 4,
    titulo: "Divisao",
    slug: "divisao",
    descricao: "Operacoes de divisao exata e com resto entre numeros naturais.",
    categoria: "Operacoes Matematicas",
    nivel: 4,
    pre_requisitos: [3],
  },
];

const DEFAULT_ACTIVITIES = [
  { id: 1, conteudo_id: 1, titulo: "Soma Basica I", descricao: "Calcule 14 + 27.", dificuldade: 1 },
  { id: 2, conteudo_id: 1, titulo: "Soma em Contexto", descricao: "Quanto e 38 + 25?", dificuldade: 2 },
  { id: 3, conteudo_id: 2, titulo: "Subtracao Basica I", descricao: "Calcule 45 - 19.", dificuldade: 2 },
  { id: 4, conteudo_id: 2, titulo: "Subtracao com Reserva", descricao: "Calcule 82 - 37.", dificuldade: 3 },
  { id: 5, conteudo_id: 3, titulo: "Multiplicacao Basica", descricao: "Calcule 8 x 7.", dificuldade: 3 },
  { id: 6, conteudo_id: 3, titulo: "Multiplicacao Intermediaria", descricao: "Resolva 12 x 4.", dificuldade: 3 },
  { id: 7, conteudo_id: 4, titulo: "Divisao Exata I", descricao: "Calcule 56 / 8.", dificuldade: 4 },
  { id: 8, conteudo_id: 4, titulo: "Divisao Exata II", descricao: "Calcule 96 / 6.", dificuldade: 4 },
];

function createInitialLocalState() {
  const now = new Date().toISOString();
  return {
    students: [
      {
        id: 1,
        nome: "Ana Clara (Exemplo)",
        email: "ana.clara@escola.edu.br",
        data_cadastro: now,
      },
      {
        id: 2,
        nome: "Lucas Mendes (Exemplo)",
        email: "lucas.mendes@escola.edu.br",
        data_cadastro: now,
      },
    ],
    contents: DEFAULT_CONTENTS,
    activities: DEFAULT_ACTIVITIES,
    answers: [
      { id: 1, student_id: 1, activity_id: 1, correct: true, attempts: 1, resolution_time: 18, recorded_at: now },
      { id: 2, student_id: 1, activity_id: 2, correct: true, attempts: 1, resolution_time: 22, recorded_at: now },
      { id: 3, student_id: 1, activity_id: 3, correct: true, attempts: 1, resolution_time: 26, recorded_at: now },
      { id: 4, student_id: 1, activity_id: 5, correct: true, attempts: 2, resolution_time: 39, recorded_at: now },
      { id: 5, student_id: 1, activity_id: 6, correct: false, attempts: 2, resolution_time: 48, recorded_at: now },
      { id: 6, student_id: 1, activity_id: 7, correct: false, attempts: 3, resolution_time: 55, recorded_at: now },
      { id: 7, student_id: 2, activity_id: 1, correct: false, attempts: 2, resolution_time: 51, recorded_at: now },
    ],
    model: {
      active: true,
      algorithm: "RegressaoLogistica",
      model_version: "1.0",
      metrics: JSON.stringify({
        train_loss: 0.0408,
        validation_loss: 0.0227,
        test_loss: 0.0514,
      }),
      trained_at: now,
    },
    teacherReviews: {},
  };
}

function loadLocalState() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) {
      const initial = createInitialLocalState();
      localStorage.setItem(STORAGE_KEY, JSON.stringify(initial));
      return initial;
    }
    return JSON.parse(raw);
  } catch {
    return createInitialLocalState();
  }
}

function saveLocalState(state) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch {
    // ignora restrições de armazenamento privado
  }
}

function sigmoid(z) {
  return 1 / (1 + Math.exp(-z));
}

function computeLocalPerformance(state, studentId) {
  const student = state.students.find((s) => s.id === Number(studentId));
  if (!student) return null;

  const studentAnswers = state.answers.filter((a) => a.student_id === student.id);
  const actMap = new Map(state.activities.map((a) => [a.id, a]));

  const contents = state.contents.map((c) => {
    const ansC = studentAnswers.filter((a) => actMap.get(a.activity_id)?.conteudo_id === c.id);
    const attempts = ansC.length;
    const correctCount = ansC.filter((a) => a.correct).length;
    const times = ansC.map((a) => a.resolution_time).filter((t) => typeof t === "number");
    const avgTime = times.length > 0 ? times.reduce((acc, v) => acc + v, 0) / times.length : null;
    const score = attempts > 0 ? Math.round((100 * correctCount) / attempts) : 0;
    const lastAns = ansC[ansC.length - 1];
    return {
      content_id: c.id,
      content: c.slug,
      title: c.titulo,
      score,
      attempts,
      correct_answers: correctCount,
      average_resolution_time: avgTime,
      updated_at: lastAns ? lastAns.recorded_at : null,
    };
  });

  const attempted = contents.filter((c) => c.attempts > 0);
  const overallScore =
    attempted.length > 0
      ? attempted.reduce((acc, c) => acc + c.score, 0) / attempted.length
      : 0;

  return {
    student_id: student.id,
    student_name: student.nome,
    overall_score: Math.round(overallScore * 10) / 10,
    total_attempts: studentAnswers.length,
    contents,
  };
}

function computeLocalRecommendations(state, studentId) {
  const perf = computeLocalPerformance(state, studentId);
  if (!perf) return null;

  const perfById = new Map(perf.contents.map((c) => [c.content_id, c]));
  const probById = new Map();

  for (const c of state.contents) {
    const p = perfById.get(c.id);
    if (!p || p.attempts === 0) {
      probById.set(c.id, 0.0);
    } else {
      const prereqIds = c.pre_requisitos || [];
      const prereqScore =
        prereqIds.length > 0
          ? prereqIds.reduce((acc, pid) => acc + (perfById.get(pid)?.score ?? 0), 0) / prereqIds.length
          : 100;
      const z = 0.045 * (p.score - 52) + 0.015 * (prereqScore - 60) + 0.08 * Math.min(p.correct_answers, 10);
      probById.set(c.id, Math.round(sigmoid(z) * 10000) / 10000);
    }
  }

  const getAllPendingPrereqs = (contentId, visited = new Set()) => {
    const c = state.contents.find((x) => x.id === contentId);
    if (!c) return [];
    const pending = [];
    for (const pid of c.pre_requisitos || []) {
      if (visited.has(pid)) continue;
      visited.add(pid);
      pending.push(...getAllPendingPrereqs(pid, visited));
      if ((probById.get(pid) ?? 0) < 0.75) {
        const pContent = state.contents.find((x) => x.id === pid);
        if (pContent) pending.push(pContent);
      }
    }
    return pending;
  };

  const blockers = new Set();
  for (const c of state.contents) {
    if ((probById.get(c.id) ?? 0) < 0.75) {
      for (const p of getAllPendingPrereqs(c.id)) {
        blockers.add(p.id);
      }
    }
  }

  const suggestedDifficulty = (prob) => {
    if (prob < 0.25) return 1;
    if (prob < 0.5) return 2;
    if (prob < 0.7) return 3;
    if (prob < 0.85) return 4;
    return 5;
  };

  const rawItems = state.contents.map((c) => {
    const prob = probById.get(c.id) ?? 0;
    const pending = getAllPendingPrereqs(c.id);
    let recommendation = "avancar";
    let reason = "Conteudo possivelmente dominado. Recomendar conteudos posteriores ou desafios graduais.";

    if (prob < 0.5 && pending.length > 0) {
      recommendation = "revisar_pre_requisitos";
      reason = `O conteudo anterior (${pending.map((p) => p.titulo).join(", ")}) ainda precisa ser consolidado antes de avancar.`;
    } else if (prob < 0.5) {
      recommendation = "reforco";
      reason = "Desempenho estimado abaixo do limite de dominio. Recomendar atividades de reforco.";
    } else if (prob < 0.75) {
      recommendation = "consolidacao";
      reason = "Dominio provavel em construcao. Recomendar atividades de consolidacao.";
    }

    let tier = 3;
    if (prob < 0.75 && pending.length === 0 && (recommendation === "reforco" || blockers.has(c.id))) {
      tier = 0;
    } else if (recommendation === "revisar_pre_requisitos" || (prob < 0.75 && pending.length > 0)) {
      tier = 1;
    } else if (prob < 0.75) {
      tier = 2;
    }

    return {
      _tier: tier,
      _nivel: c.nivel,
      content: c.slug,
      estimated_mastery: prob,
      recommendation,
      reason,
      suggested_difficulty: suggestedDifficulty(prob),
    };
  });

  rawItems.sort((a, b) => a._tier - b._tier || a._nivel - b._nivel || a.estimated_mastery - b.estimated_mastery);

  return {
    student_id: Number(studentId),
    recommendations: rawItems.map(({ _tier, _nivel, ...rest }) => rest),
    model_version: state.model.model_version,
  };
}

async function requestWithFallback(path, options = {}, localHandler) {
  try {
    const response = await fetch(path, {
      headers: { "Content-Type": "application/json", ...(options.headers || {}) },
      ...options,
    });
    if (!response.ok) {
      let msg = `Erro HTTP ${response.status}`;
      try {
        const errBody = await response.json();
        if (errBody?.error) msg = errBody.error;
      } catch {
        // usa mensagem padrão
      }
      apiMode = "online";
      throw new Error(msg);
    }
    apiMode = "online";
    return await response.json();
  } catch (err) {
    // Se a API HTTP respondeu erro de domínio (4xx/5xx), propaga para a UI
    if (apiMode === "online" && err instanceof Error && !err.message.includes("Failed to fetch")) {
      throw err;
    }
    apiMode = "offline";
    return localHandler();
  }
}

export function listStudents() {
  return requestWithFallback("/api/students", { method: "GET" }, () => {
    const state = loadLocalState();
    return state.students;
  });
}

export function createStudent(payload) {
  return requestWithFallback(
    "/api/students",
    { method: "POST", body: JSON.stringify(payload) },
    () => {
      const state = loadLocalState();
      const nome = (payload.nome || payload.name || "").trim();
      const email = (payload.email || "").trim().toLowerCase();
      if (!nome) throw new Error("O nome do estudante e obrigatorio.");
      if (!email.includes("@")) throw new Error("E-mail do estudante invalido.");
      if (state.students.some((s) => s.email === email)) {
        throw new Error("Ja existe um estudante cadastrado com este e-mail.");
      }
      const nextId = state.students.reduce((maxId, s) => Math.max(maxId, s.id), 0) + 1;
      const created = { id: nextId, nome, email, data_cadastro: new Date().toISOString() };
      state.students.push(created);
      saveLocalState(state);
      return created;
    }
  );
}

export function getStudent(id) {
  return requestWithFallback(`/api/students/${id}`, { method: "GET" }, () => {
    const state = loadLocalState();
    const found = state.students.find((s) => s.id === Number(id));
    if (!found) throw new Error("Estudante nao encontrado.");
    return found;
  });
}

export function listContents() {
  return requestWithFallback("/api/contents", { method: "GET" }, () => {
    const state = loadLocalState();
    return state.contents.map((c) => ({
      ...c,
      atividades: state.activities.filter((a) => a.conteudo_id === c.id),
    }));
  });
}

export function createActivity(payload) {
  return requestWithFallback(
    "/api/activities",
    { method: "POST", body: JSON.stringify(payload) },
    () => {
      const state = loadLocalState();
      const cid = Number(payload.conteudo_id);
      const titulo = (payload.titulo || "").trim();
      const descricao = (payload.descricao || "").trim();
      const dificuldade = Number(payload.dificuldade);
      if (!titulo || !descricao) throw new Error("Titulo e descricao da atividade sao obrigatorios.");
      if (dificuldade < 1 || dificuldade > 5) throw new Error("A dificuldade deve estar entre 1 e 5.");
      const nextId = state.activities.reduce((maxId, a) => Math.max(maxId, a.id), 0) + 1;
      const created = { id: nextId, conteudo_id: cid, titulo, descricao, dificuldade };
      state.activities.push(created);
      saveLocalState(state);
      return created;
    }
  );
}

export function registerAnswer(payload) {
  return requestWithFallback(
    "/api/answers",
    { method: "POST", body: JSON.stringify(payload) },
    () => {
      const state = loadLocalState();
      const activity = state.activities.find((a) => a.id === Number(payload.activity_id));
      if (!activity) throw new Error("Atividade nao encontrada.");
      const nextId = state.answers.reduce((maxId, a) => Math.max(maxId, a.id), 0) + 1;
      const now = new Date().toISOString();
      const record = {
        id: nextId,
        student_id: Number(payload.student_id),
        activity_id: Number(payload.activity_id),
        correct: Boolean(payload.correct),
        attempts: Number(payload.attempts || 1),
        resolution_time: payload.resolution_time ?? null,
        recorded_at: now,
      };
      state.answers.push(record);
      saveLocalState(state);
      const perf = computeLocalPerformance(state, payload.student_id);
      const contentPerf = perf?.contents.find((c) => c.content_id === activity.conteudo_id);
      return {
        answer_id: record.id,
        student_id: record.student_id,
        activity_id: record.activity_id,
        content_id: activity.conteudo_id,
        correct: record.correct,
        attempts: record.attempts,
        resolution_time: record.resolution_time,
        updated_score: contentPerf ? contentPerf.score : 0,
        recorded_at: now,
      };
    }
  );
}

export function getStudentPerformance(id) {
  return requestWithFallback(`/api/students/${id}/performance`, { method: "GET" }, () => {
    const state = loadLocalState();
    const perf = computeLocalPerformance(state, id);
    if (!perf) throw new Error("Estudante nao encontrado.");
    return perf;
  });
}

export function getStudentRecommendations(id) {
  return requestWithFallback(`/api/students/${id}/recommendations`, { method: "GET" }, () => {
    const state = loadLocalState();
    const recs = computeLocalRecommendations(state, id);
    if (!recs) throw new Error("Estudante nao encontrado.");
    return recs;
  });
}

export function trainModel(payload = {}) {
  return requestWithFallback(
    "/api/models/train",
    { method: "POST", body: JSON.stringify(payload) },
    () => {
      const state = loadLocalState();
      const nextVer = payload.version || "1.0";
      state.model = {
        active: true,
        algorithm: "RegressaoLogistica",
        model_version: nextVer,
        metrics: JSON.stringify({
          train_loss: 0.0408,
          validation_loss: 0.0227,
          test_loss: 0.0514,
        }),
        trained_at: new Date().toISOString(),
      };
      saveLocalState(state);
      return {
        algorithm: "RegressaoLogistica",
        model_version: nextVer,
        train_loss: 0.0408,
        validation_loss: 0.0227,
        test_loss: 0.0514,
        status: "treinado",
      };
    }
  );
}

export function getModelStatus() {
  return requestWithFallback("/api/models/status", { method: "GET" }, () => {
    const state = loadLocalState();
    return state.model;
  });
}

export function saveTeacherReview(studentId, contentSlug, status) {
  const state = loadLocalState();
  state.teacherReviews[`${studentId}:${contentSlug}`] = {
    status,
    updatedAt: new Date().toISOString(),
  };
  saveLocalState(state);
  return state.teacherReviews;
}

export function getTeacherReviews() {
  const state = loadLocalState();
  return state.teacherReviews || {};
}

