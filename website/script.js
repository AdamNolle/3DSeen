const modes = {
  object: {
    label: 'MODE 01 / OBJECT',
    title: 'Subject-aware object guidance',
    description: 'Vision locks onto the foreground subject. ARKit supplies tracked feature points or LiDAR depth where available, while quality gates decide when an automatic photo is useful.'
  },
  space: {
    label: 'MODE 02 / ROOMS & SPACES',
    title: 'Visible surfaces, measured in depth',
    description: 'On supported LiDAR hardware, ARKit surface meshes and depth-checked camera projections make a textured room model. Unseen faces stay neutral and coverage refers only to observed geometry.'
  },
  landscape: {
    label: 'MODE 03 / LANDSCAPE',
    title: 'Outdoor frames in context',
    description: 'Landscape mode uses ARKit world tracking and retained image frames without requiring LiDAR. The capture remains grounded in frames the camera actually recorded.'
  }
};

const display = document.querySelector('[data-mode-display]');
const buttons = document.querySelectorAll('[data-mode]');

for (const button of buttons) {
  button.addEventListener('click', () => {
    const selected = button.dataset.mode;
    const mode = modes[selected];
    display.dataset.modeDisplay = selected;
    display.querySelector('.display-top span:first-child').textContent = mode.label;
    document.querySelector('#mode-title').textContent = mode.title;
    document.querySelector('#mode-description').textContent = mode.description;
    for (const choice of buttons) {
      const active = choice === button;
      choice.classList.toggle('active', active);
      choice.setAttribute('aria-pressed', String(active));
    }
  });
}
