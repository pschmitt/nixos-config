export const TmuxContextPlugin = async () => {
  const pane = process.env.TMUX_PANE

  if (!pane) {
    return {}
  }

  return {
    "experimental.chat.system.transform": async (_input, output) => {
      output.system.push(
        `This OpenCode agent is running in tmux pane ${pane}. Before doing task work, choose a concise window name that describes the user's current request and rename this pane's window with: tmux rename-window -t '${pane}' 'short-task-name'. Use this explicit pane target; never rename the active window by assumption.`,
      )
    },
  }
}
