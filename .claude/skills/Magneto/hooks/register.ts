import type { Register } from 'claude-code'
import { buildStatus } from './build-status'
import { guardrails } from './guardrails'

// One plugin per app, named after it: its toasts and status line carry that name.
export const register: Register = (on, options) => {
  guardrails(on, options)
  buildStatus(on, options)
}
