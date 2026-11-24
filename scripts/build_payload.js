const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const themesPath = path.join(repoRoot, 'themes', 'themes.json');
const enginePath = path.join(repoRoot, 'engine', 'core.js');
const outPath = path.join(repoRoot, 'dist', 'theme_payload.js');

const ASSET_KEYS = ['wallpaper', 'sticker', 'cornerSvg', 'userAvatar', 'agentAvatar'];
const PLACEHOLDER = '/*__THEMES_PLACEHOLDER__*/{}';
const BOOT_ASSETS_PLACEHOLDER = '/*__BOOT_ASSETS_PLACEHOLDER__*/{}';

function getMimeType(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  switch (ext) {
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.png':
      return 'image/png';
    case '.webp':
      return 'image/webp';
    case '.svg':
      return 'image/svg+xml';
    case '.mp4':
      return 'video/mp4';
    case '.woff2':
      return 'font/woff2';
    case '.wav':
      return 'audio/wav';
    case '.mp3':
      return 'audio/mpeg';
    default:
      return 'application/octet-stream';
  }
}

function encodeAsset(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  if (ext === '.svg') {
    const text = fs.readFileSync(filePath, 'utf-8');
    return 'data:image/svg+xml,' + encodeURIComponent(text);
  }
  const buf = fs.readFileSync(filePath);
  const mime = getMimeType(filePath);
  return `data:${mime};base64,${buf.toString('base64')}`;
}

function resolveAsset(val, themesDir) {
  if (typeof val !== 'string') return val;
  const trimmed = val.trim();
  if (!trimmed || trimmed.startsWith('data:') || trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  let assetPath = trimmed;
  if (!path.isAbsolute(assetPath)) {
    assetPath = path.resolve(themesDir, assetPath);
  }
  if (!fs.existsSync(assetPath)) {
    throw new Error(`Asset not found: ${trimmed} (${assetPath})`);
  }
  return encodeAsset(assetPath);
}

function build() {
  const themesDir = path.dirname(themesPath);
  const themesRaw = JSON.parse(fs.readFileSync(themesPath, 'utf-8'));
  const resolvedThemes = {};

  for (const [name, cfg] of Object.entries(themesRaw)) {
    const copy = { ...cfg };
    for (const key of ASSET_KEYS) {
      if (key in copy) {
        copy[key] = resolveAsset(copy[key], themesDir);
      }
    }
    resolvedThemes[name] = copy;
  }

  let engineSrc = fs.readFileSync(enginePath, 'utf-8');
  if (!engineSrc.includes(PLACEHOLDER)) {
    throw new Error(`Placeholder ${PLACEHOLDER} not found in ${enginePath}`);
  }
  let compiled = engineSrc.replace(PLACEHOLDER, JSON.stringify(resolvedThemes));

  if (compiled.includes(BOOT_ASSETS_PLACEHOLDER)) {
    const assetsDir = path.join(themesDir, 'assets');
    const bootCandidates = {
      starfieldBg: path.join(assetsDir, 'starfield-boot-bg.jpg'),
      agyColorIcon: path.join(assetsDir, 'agy-icon-color.png'),
      voice1: fs.existsSync(path.join(assetsDir, 'voice', 'tawa_voice1.wav')) ? path.join(assetsDir, 'voice', 'tawa_voice1.wav') : path.join(assetsDir, 'voice', 'tawa_voice1.mp3'),
      voice2: fs.existsSync(path.join(assetsDir, 'voice', 'tawa_voice2.wav')) ? path.join(assetsDir, 'voice', 'tawa_voice2.wav') : path.join(assetsDir, 'voice', 'tawa_voice2.mp3'),
      voice3: fs.existsSync(path.join(assetsDir, 'voice', 'tawa_voice3.wav')) ? path.join(assetsDir, 'voice', 'tawa_voice3.wav') : path.join(assetsDir, 'voice', 'tawa_voice3.mp3'),
      voice4: fs.existsSync(path.join(assetsDir, 'voice', 'tawa_voice4.wav')) ? path.join(assetsDir, 'voice', 'tawa_voice4.wav') : path.join(assetsDir, 'voice', 'tawa_voice4.mp3'),
      greetingFontVi: path.join(assetsDir, 'fonts', 'mali-500-vi.woff2'),
      greetingFontLatinExt: path.join(assetsDir, 'fonts', 'mali-500-latin-ext.woff2'),
      greetingFontLatin: path.join(assetsDir, 'fonts', 'mali-500-latin.woff2'),
    };
    const bootAssets = {};
    for (const [key, filePath] of Object.entries(bootCandidates)) {
      if (fs.existsSync(filePath)) {
        bootAssets[key] = encodeAsset(filePath);
      }
    }
    compiled = compiled.replace(BOOT_ASSETS_PLACEHOLDER, JSON.stringify(bootAssets));
  }

  const outDir = path.dirname(outPath);
  if (!fs.existsSync(outDir)) {
    fs.mkdirSync(outDir, { recursive: true });
  }
  fs.writeFileSync(outPath, compiled, 'utf-8');
  const sizeKb = (fs.statSync(outPath).size / 1024).toFixed(1);
  console.log(`[build_payload.js] Built ${outPath} (${sizeKb} KB) with ${Object.keys(resolvedThemes).length} theme(s): ${Object.keys(resolvedThemes).join(', ')}`);
}

build();
