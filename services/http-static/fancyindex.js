(() => {
  const root = document.documentElement;
  const themeToggle = document.querySelector("#theme-toggle");
  const filterInput = document.querySelector("#file-filter");
  const resultsCount = document.querySelector("#results-count");
  const emptyState = document.querySelector("#empty-state");
  const rows = [...document.querySelectorAll("#list tbody tr")];
  const parentRow = rows.find((row) =>
    row.querySelector("td.link a")?.textContent.startsWith("Parent directory"),
  );
  const fileRows = rows.filter((row) => row !== parentRow);
  const themeKey = "blobs-theme";
  const systemTheme = window.matchMedia("(prefers-color-scheme: dark)");

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
