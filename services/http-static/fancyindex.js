(() => {
  const root = document.documentElement;
  const currentPath = window.location.pathname;
  const currentDirectory = document.querySelector("#current-directory");
  document.title = `blobs - ${currentPath}`;
  currentDirectory.title = currentPath;
  currentDirectory.setAttribute("aria-label", currentPath);

  const pathCanvas = document.createElement("canvas");
  const pathContext = pathCanvas.getContext("2d");

  function renderCurrentPath() {
    const font = window.getComputedStyle(currentDirectory).font;
    const availableWidth = currentDirectory.clientWidth;
    pathContext.font = font;

    function fits(text) {
      return pathContext.measureText(text).width <= availableWidth;
    }

    if (fits(currentPath)) {
      currentDirectory.textContent = currentPath;
      return;
    }

    const segments = currentPath.split("/").filter(Boolean);
    let abbreviated = null;
    let bestVisibleCount = -1;
    let bestBalance = Infinity;

    for (let leading = 1; leading < segments.length; leading += 1) {
      for (let trailing = 1; leading + trailing < segments.length; trailing += 1) {
        const candidate = `/${segments.slice(0, leading).join("/")}/…/${segments.slice(-trailing).join("/")}/`;
        const visibleCount = leading + trailing;
        const balance = Math.abs(leading - trailing);
        if (
          fits(candidate)
          && (visibleCount > bestVisibleCount || (visibleCount === bestVisibleCount && balance < bestBalance))
        ) {
          abbreviated = candidate;
          bestVisibleCount = visibleCount;
          bestBalance = balance;
        }
      }
    }

    if (!abbreviated) {
      for (let keep = Math.floor((currentPath.length - 1) / 2); keep > 0; keep -= 1) {
        const candidate = `${currentPath.slice(0, keep)}…${currentPath.slice(-keep)}`;
        if (fits(candidate)) {
          abbreviated = candidate;
          break;
        }
      }
    }

    currentDirectory.textContent = abbreviated || "…";
  }

  const pathResizeObserver = new ResizeObserver(renderCurrentPath);
  pathResizeObserver.observe(currentDirectory);
  renderCurrentPath();

  const themeToggle = document.querySelector("#theme-toggle");
  const filterInput = document.querySelector("#file-filter");
  const resultsCount = document.querySelector("#results-count");
  const listSummary = document.querySelector("#list-summary");
  const emptyState = document.querySelector("#empty-state");
  const rows = [...document.querySelectorAll("#list tbody tr")];
  const parentRow = rows.find((row) =>
    row.querySelector("td.link a")?.textContent.startsWith("Parent directory"),
  );
  if (parentRow) {
    parentRow.classList.add("parent-directory");
    parentRow.querySelector("td.link a").textContent = "..";
  }
  const fileRows = rows.filter((row) => row !== parentRow);
  const themeKey = "blobs-theme";
  const systemTheme = window.matchMedia("(prefers-color-scheme: dark)");
  const sizeMultipliers = {
    B: 1,
    KB: 1000,
    MB: 1000 ** 2,
    GB: 1000 ** 3,
    TB: 1000 ** 4,
    KIB: 1024,
    MIB: 1024 ** 2,
    GIB: 1024 ** 3,
    TIB: 1024 ** 4,
  };

  function parseDisplayedSize(value) {
    const match = value.trim().match(/^([\d.]+)\s*(B|KB|MB|GB|TB|KIB|MIB|GIB|TIB)$/i);
    if (!match) return null;
    return Number(match[1]) * sizeMultipliers[match[2].toUpperCase()];
  }

  function formatSize(bytes) {
    const units = ["B", "KiB", "MiB", "GiB", "TiB"];
    let size = bytes;
    let unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex += 1;
    }
    const digits = unitIndex === 0 || size >= 100 ? 0 : 1;
    return `${size.toFixed(digits)} ${units[unitIndex]}`;
  }

  function updateListSummary() {
    const files = fileRows
      .filter((row) => !row.hidden)
      .map((row) => parseDisplayedSize(row.querySelector("td.size")?.textContent ?? ""))
      .filter((size) => size !== null);
    const totalSize = files.reduce((total, size) => total + size, 0);
    const fileCount = files.length;
    const fileLabel = `${fileCount} ${fileCount === 1 ? "file" : "files"}`;
    const sizeLabel = fileCount ? ` · about ${formatSize(totalSize)} total` : "";

    listSummary.textContent = `${fileLabel}${sizeLabel}`;
  }

  function savedTheme() {
    try {
      const theme = localStorage.getItem(themeKey);
      return theme === "light" || theme === "dark" ? theme : null;
    } catch {
      return null;
    }
  }

  function applyTheme(theme) {
    if (theme) {
      root.dataset.theme = theme;
    } else {
      delete root.dataset.theme;
    }

    const isDark = theme ? theme === "dark" : systemTheme.matches;
    const nextTheme = isDark ? "light" : "dark";
    themeToggle.dataset.nextTheme = nextTheme;
    themeToggle.setAttribute("aria-label", `Switch to ${nextTheme} mode`);
    themeToggle.setAttribute("title", `Switch to ${nextTheme} mode`);
    themeToggle.setAttribute("aria-pressed", String(isDark));
  }

  function filterFiles() {
    const query = filterInput.value.trim().toLocaleLowerCase();
    let visible = 0;
    fileRows.forEach((row) => {
      const link = row.querySelector("td.link a");
      const matches = !query || link?.textContent.toLocaleLowerCase().includes(query);
      row.hidden = !matches;
      if (matches) visible += 1;
    });

    if (parentRow) parentRow.hidden = Boolean(query);
    resultsCount.textContent = `${visible} ${visible === 1 ? "item" : "items"}`;
    emptyState.hidden = visible !== 0;
    updateListSummary();
  }

  const currentTheme = savedTheme();
  applyTheme(currentTheme);
  filterFiles();

  themeToggle.addEventListener("click", () => {
    const isDark = root.dataset.theme
      ? root.dataset.theme === "dark"
      : systemTheme.matches;
    const theme = isDark ? "light" : "dark";
    try {
      localStorage.setItem(themeKey, theme);
    } catch {
      // Theme changes still work for this page when storage is unavailable.
    }
    applyTheme(theme);
  });

  systemTheme.addEventListener("change", () => {
    if (!savedTheme()) applyTheme(null);
  });
  filterInput.addEventListener("input", filterFiles);
})();
