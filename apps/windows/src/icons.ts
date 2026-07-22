/** Small inline SVG icons (Windows shell has no SF Symbols). */

const stroke = `fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"`;

export function icon(name: string, size = 18): string {
  const common = `width="${size}" height="${size}" viewBox="0 0 24 24" aria-hidden="true" ${stroke}`;
  switch (name) {
    case "home":
      return `<svg ${common}><path d="M3 10.5 12 3l9 7.5"/><path d="M5 10v10h14V10"/></svg>`;
    case "nodes":
      return `<svg ${common}><circle cx="6" cy="6" r="2.2"/><circle cx="18" cy="6" r="2.2"/><circle cx="12" cy="18" r="2.2"/><path d="M7.8 7.2 10.8 16"/><path d="M16.2 7.2 13.2 16"/><path d="M8.2 6h7.6"/></svg>`;
    case "profile":
      return `<svg ${common}><path d="M7 4h7l3 3v13H7z"/><path d="M14 4v3h3"/></svg>`;
    case "logs":
      return `<svg ${common}><path d="M5 6h14"/><path d="M5 12h14"/><path d="M5 18h10"/></svg>`;
    case "settings":
      return `<svg ${common}><circle cx="12" cy="12" r="3"/><path d="M12 3v2.2M12 18.8V21M4.9 6.5l1.6 1.1M17.5 16.4l1.6 1.1M3 12h2.2M18.8 12H21M4.9 17.5l1.6-1.1M17.5 7.6l1.6-1.1"/></svg>`;
    case "play":
      return `<svg ${common}><path d="M8 6.5v11l9-5.5z"/></svg>`;
    case "stop":
      return `<svg ${common}><rect x="7" y="7" width="10" height="10" rx="1.5"/></svg>`;
    case "refresh":
      return `<svg ${common}><path d="M20 12a8 8 0 1 1-2.3-5.6"/><path d="M20 5v5h-5"/></svg>`;
    case "check":
      return `<svg ${common}><path d="M5 12.5 10 17l9-10"/></svg>`;
    case "warn":
      return `<svg ${common}><path d="M12 4 21 19H3z"/><path d="M12 10v4"/><path d="M12 16.5h.01"/></svg>`;
    case "x":
      return `<svg ${common}><path d="M7 7l10 10M17 7 7 17"/></svg>`;
    case "copy":
      return `<svg ${common}><rect x="8" y="8" width="11" height="11" rx="1.5"/><path d="M5 15V5h10"/></svg>`;
    case "globe":
      return `<svg ${common}><circle cx="12" cy="12" r="8"/><path d="M4 12h16M12 4c2.5 2.8 2.5 13.2 0 16M12 4c-2.5 2.8-2.5 13.2 0 16"/></svg>`;
    case "network":
      return `<svg ${common}><path d="M4 16h16"/><path d="M7 16v-3h10v3"/><path d="M9 13V8h6v5"/><path d="M12 8V4"/></svg>`;
    case "shield":
      return `<svg ${common}><path d="M12 3 5 6v6c0 4.5 3 7.5 7 9 4-1.5 7-4.5 7-9V6z"/></svg>`;
    case "arrow-up":
      return `<svg ${common}><path d="M12 19V5M6 11l6-6 6 6"/></svg>`;
    case "arrow-down":
      return `<svg ${common}><path d="M12 5v14M6 13l6 6 6-6"/></svg>`;
    case "info":
      return `<svg ${common}><circle cx="12" cy="12" r="8"/><path d="M12 11v5M12 8h.01"/></svg>`;
    case "trash":
      return `<svg ${common}><path d="M5 7h14"/><path d="M9 7V5h6v2"/><path d="M8 7l1 12h6l1-12"/></svg>`;
    case "search":
      return `<svg ${common}><circle cx="11" cy="11" r="6"/><path d="M16 16l4 4"/></svg>`;
    case "sort":
      return `<svg ${common}><path d="M8 7h12M8 12h8M8 17h4"/><path d="M4 7v10M4 17l-2-2M4 17l2-2"/></svg>`;
    case "params":
      return `<svg ${common}><path d="M4 7h10M18 7h2M14 5v4M4 17h4M12 17h8M8 15v4"/></svg>`;
    case "export":
      return `<svg ${common}><path d="M12 4v10"/><path d="M8 8l4-4 4 4"/><path d="M5 16v3h14v-3"/></svg>`;
    default:
      return `<svg ${common}><circle cx="12" cy="12" r="7"/></svg>`;
  }
}
