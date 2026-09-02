#!/usr/bin/env node
/**
 * Выгрузка констант баланса из JS-оригинала 5GOR в JSON.
 *
 * Прямой импорт модулей невозможен: они тянут three.js и DOM. Поэтому нужные
 * константы вырезаются из текста балансировкой скобок (с учётом строк и
 * комментариев) и вычисляются изолированно. Побочных эффектов модулей нет.
 *
 * Usage: node tools/dump_data.mjs [путь-к-оригиналу]
 * По умолчанию: ../../5gor относительно этого проекта.
 */

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = resolve(process.argv[2] ?? join(HERE, '..', '..', '..', '5gor'), 'src');
const OUT = join(HERE, 'dump');

/** Пропускает строковый литерал или комментарий, возвращает индекс после него. */
function skipNonCode(s, i) {
  const c = s[i];
  if (c === '/' && s[i + 1] === '/') {
    const nl = s.indexOf('\n', i);
    return nl === -1 ? s.length : nl;
  }
  if (c === '/' && s[i + 1] === '*') {
    const end = s.indexOf('*/', i + 2);
    return end === -1 ? s.length : end + 2;
  }
  if (c === '"' || c === "'" || c === '`') {
    let j = i + 1;
    while (j < s.length) {
      if (s[j] === '\\') { j += 2; continue; }
      if (s[j] === c) return j + 1;
      j++;
    }
    return s.length;
  }
  return -1;
}

/** Вырезает значение присваивания `<prefix> = <literal>` с балансировкой скобок. */
function extractAssignment(src, re, label) {
  const m = re.exec(src);
  if (!m) throw new Error(`не найдено объявление ${label}`);

  let i = m.index + m[0].length;
  const open = src[i];
  if (open !== '[' && open !== '{') {
    // Скаляр или выражение — читаем до `;` на верхнем уровне.
    const semi = src.indexOf(';', i);
    return src.slice(i, semi);
  }
  const close = open === '[' ? ']' : '}';
  let depth = 0;
  while (i < src.length) {
    const skipped = skipNonCode(src, i);
    if (skipped !== -1) { i = skipped; continue; }
    const c = src[i];
    if (c === open) depth++;
    else if (c === close) {
      depth--;
      if (depth === 0) return src.slice(m.index + m[0].length, i + 1);
    }
    i++;
  }
  throw new Error(`не сбалансированы скобки в ${label}`);
}

/** Вырезает `const NAME = <literal>` (в т.ч. с `export`). */
function extractConst(src, name) {
  return extractAssignment(
    src, new RegExp(`^(?:export\\s+)?const\\s+${name}\\s*=\\s*`, 'm'), `const ${name}`);
}

/** Вырезает `this.NAME = <literal>` — таблицы, объявленные внутри конструктора. */
function extractField(src, name) {
  return extractAssignment(
    src, new RegExp(`this\\.${name}\\s*=\\s*`), `this.${name}`);
}

/** Вычисляет вырезанный литерал. Math доступен (CFG использует Math.PI). */
function evalLiteral(code, name) {
  try {
    return new Function('Math', `"use strict"; return (${code});`)(Math);
  } catch (e) {
    throw new Error(`не удалось вычислить ${name}: ${e.message}`);
  }
}

const cache = new Map();
function read(file) {
  if (!cache.has(file)) cache.set(file, readFileSync(join(SRC, file), 'utf8'));
  return cache.get(file);
}

function grab(file, name) {
  return evalLiteral(extractConst(read(file), name), `${file}:${name}`);
}

/** Собирает набор пулов реплик из файла: { ключ: имя_const }. */
function grabQuotes(file, names) {
  const out = {};
  for (const [key, constName] of Object.entries(names)) {
    out[key] = grab(file, constName);
  }
  return out;
}

// --- config.js: чистый, без импортов -----------------------------------------
const config = {
  CFG: grab('config.js', 'CFG'),
  CFG_GFX_PRESETS: grab('config.js', 'CFG_GFX_PRESETS'),
  MOOD_TIERS: grab('config.js', 'MOOD_TIERS'),
  DISTRICTS: grab('config.js', 'DISTRICTS'),
  PALETTES: grab('config.js', 'PALETTES'),
  UPGRADES: grab('config.js', 'UPGRADES'),
  CARS: grab('config.js', 'CARS'),
  CAR_TYPE_SHAPE: grab('config.js', 'CAR_TYPE_SHAPE'),
  TUNING: grab('config.js', 'TUNING'),
  LANDMARKS: grab('config.js', 'LANDMARKS'),
  FUEL_STATIONS: grab('config.js', 'FUEL_STATIONS'),
  WEATHER_DEFS: grab('config.js', 'WEATHER_DEFS'),
};

// --- orders.js ---------------------------------------------------------------
const orders = {
  ORDER_META: grab('orders.js', 'ORDER_META'),
  REVIEWS: grab('orders.js', 'REVIEWS'),
};

// --- traffic.js --------------------------------------------------------------
const traffic = {
  TRAFFIC_TYPES: grab('traffic.js', 'TRAFFIC_TYPES'),
  quotes: grabQuotes('traffic.js', {
    ram: 'DRIVER_RAM_QUOTES',
    ped: 'DRIVER_PED_QUOTES',
    ped_jwalk: 'DRIVER_PED_JWALK_QUOTES',
    hit_ped: 'DRIVER_HIT_PED_QUOTES',
    ped_reply: 'PED_REPLY_QUOTES',
    ped_reply_jwalk: 'PED_REPLY_JWALK_QUOTES',
  }),
};

// --- police.js ---------------------------------------------------------------
const police = { VIOLATIONS: grab('police.js', 'VIOLATIONS') };

// --- dialogues.js ------------------------------------------------------------
const dialogues = {
  PASSENGER_NAMES: grab('dialogues.js', 'PASSENGER_NAMES'),
  CLIENT_AVATARS: grab('dialogues.js', 'CLIENT_AVATARS'),
  PEDESTRIAN_SHOUTS: grab('dialogues.js', 'PEDESTRIAN_SHOUTS'),
  DRIVER_SHOUTS: grab('dialogues.js', 'DRIVER_SHOUTS'),
  PASSENGER_DRIFT_REACTIONS: grab('dialogues.js', 'PASSENGER_DRIFT_REACTIONS'),
  DIALOGUES: grab('dialogues.js', 'DIALOGUES'),
  WEATHER_DIALOGUES: grab('dialogues.js', 'WEATHER_DIALOGUES'),
  DISPATCHER_BRIEFS: grab('dialogues.js', 'DISPATCHER_BRIEFS'),
  DRIVER_DAY_NOTES: grab('dialogues.js', 'DRIVER_DAY_NOTES'),
};

// --- peds.js: пулы реплик по архетипам и ситуациям ---------------------------
const PED_QUOTE_CONSTS = {};
{
  const src = read('peds.js');
  const re = /^const\s+([A-Z][A-Z0-9_]*_QUOTES)\s*=/gm;
  let m;
  while ((m = re.exec(src)) !== null) PED_QUOTE_CONSTS[m[1]] = m[1];
}
const peds = {
  PED_COLORS: grab('peds.js', 'PED_COLORS'),
  quotes: grabQuotes('peds.js', PED_QUOTE_CONSTS),
};

// --- achievements.js ---------------------------------------------------------
// `check` — стрелочные функции вида `s => s.X >= N` (иногда конъюнкция 2-3
// таких). Разбираем их в декларативные условия: в порте они становятся
// AchievementReq и получают прогресс-бар бесплатно.
const camelToSnake = (s) => s.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();

function parseCheck(src, id) {
  // Убираем защитные `(s.x || 0)` — на семантику сравнения они не влияют.
  const norm = src.replace(/\(\s*s\.(\w+)\s*\|\|\s*0\s*\)/g, 's.$1');
  const parts = norm.split('&&');
  const reqs = [];
  for (const part of parts) {
    const m = /s\.(\w+)\s*(>=|<=|===|==|>|<)\s*(-?[\d.]+)/.exec(part);
    if (!m) throw new Error(`ачивка ${id}: не разобрано условие «${part.trim()}»`);
    const [, stat, cmp, value] = m;
    let op;
    if (cmp === '>=' || cmp === '>') op = 'GE';
    else if (cmp === '<=' || cmp === '<') op = 'LE';
    else op = 'EQ';
    reqs.push({ stat: camelToSnake(stat), op, value: Number(value) });
  }
  return reqs;
}

const achievementsRaw = grab('achievements.js', 'ACHIEVEMENTS');
const achievements = achievementsRaw.map((a) => {
  const requirements = parseCheck(String(a.check), a.id);
  // Прогресс-бар осмыслен только для одиночного накопительного условия.
  const single = requirements.length === 1 && requirements[0].op === 'GE';
  return {
    id: a.id, name: a.name, desc: a.desc, toast: a.toast, icon: a.icon,
    requirements,
    track_stat: single ? requirements[0].stat : '',
    track_target: single ? requirements[0].value : 0,
  };
});

// --- audio: станции радио, громкости шин, бюджеты голосов --------------------
const audio = {
  STATIONS: evalLiteral(extractField(read('audiomusic.js'), 'stations'),
    'audiomusic.js:this.stations'),
  RADIO_FALLBACK_FREQS: grab('audiomusic.js', 'RADIO_FALLBACK_FREQS'),
  AU_DEFAULT_VOL: grab('audiocore.js', 'AU_DEFAULT_VOL'),
  AU_BUDGET: grab('audiocore.js', 'AU_BUDGET'),
  AU_COOLDOWN: grab('audiocore.js', 'AU_COOLDOWN'),
  AU_NOISE_LENGTHS: grab('audiocore.js', 'AU_NOISE_LENGTHS'),
};

mkdirSync(OUT, { recursive: true });
const files = { config, orders, traffic, police, dialogues, peds, achievements, audio };
let totalKeys = 0;
for (const [name, data] of Object.entries(files)) {
  const path = join(OUT, `${name}.json`);
  writeFileSync(path, JSON.stringify(data, null, 1), 'utf8');
  const n = Array.isArray(data) ? data.length : Object.keys(data).length;
  totalKeys += n;
  console.log(`${name}.json — ${n} записей верхнего уровня`);
}
console.log(`\nВсего: ${Object.keys(files).length} файлов, ${totalKeys} записей`);
console.log(`Пулов реплик пешеходов: ${Object.keys(peds.quotes).length}`);
