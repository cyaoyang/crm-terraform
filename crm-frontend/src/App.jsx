import { useState, useEffect } from 'react'
import './App.css'

const API_BASE = 'https://gjy07kjla3.execute-api.ap-southeast-1.amazonaws.com'
const COGNITO_REGION = 'ap-southeast-1'
const COGNITO_CLIENT_ID = 'kru9k0dgg0l5jkpvtuj6m535k'
const COGNITO_ENDPOINT = `https://cognito-idp.${COGNITO_REGION}.amazonaws.com/`

const STAGE_COLORS = {
  current: '#4a9d5f', special_mention: '#c9a227', substandard: '#d97b29',
  doubtful: '#d9552d', loss: '#b03a2e', legal_escalation: '#8b2fc9', resolved: '#5a6b7a',
}
const EVENT_ICONS = { call: '📞', reminder_email: '✉️', legal_letter: '⚖️' }

function StageBadge({ stage }) {
  const color = STAGE_COLORS[stage] || '#5a6b7a'
  return (
    <span style={{ backgroundColor: color, color: '#fff', padding: '3px 10px', borderRadius: '12px', fontSize: '12px', fontWeight: 500, textTransform: 'capitalize' }}>
      {stage.replace(/_/g, ' ')}
    </span>
  )
}

function decodeToken(token) {
  try {
    const payload = token.split('.')[1]
    const json = atob(payload.replace(/-/g, '+').replace(/_/g, '/'))
    return JSON.parse(json)
  } catch {
    return {}
  }
}

async function login(email, password) {
  const res = await fetch(COGNITO_ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-amz-json-1.1', 'X-Amz-Target': 'AWSCognitoIdentityProviderService.InitiateAuth' },
    body: JSON.stringify({ AuthFlow: 'USER_PASSWORD_AUTH', ClientId: COGNITO_CLIENT_ID, AuthParameters: { USERNAME: email, PASSWORD: password } }),
  })
  const data = await res.json()
  if (!res.ok) throw new Error(data.message || 'Login failed')
  return data.AuthenticationResult.IdToken
}

function LoginForm({ onLogin }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState(null)
  const [submitting, setSubmitting] = useState(false)

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError(null)
    setSubmitting(true)
    try {
      const token = await login(email, password)
      onLogin(token)
    } catch (err) {
      setError(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="login-container">
      <form className="login-form" onSubmit={handleSubmit}>
        <h2>Collections CRM Login</h2>
        <input type="email" placeholder="Email" value={email} onChange={(e) => setEmail(e.target.value)} required />
        <input type="password" placeholder="Password" value={password} onChange={(e) => setPassword(e.target.value)} required />
        {error && <p className="login-error">{error}</p>}
        <button type="submit" disabled={submitting}>{submitting ? 'Logging in...' : 'Log in'}</button>
      </form>
    </div>
  )
}

function LogCallModal({ account, officers, token, onClose, onSuccess }) {
  const [officerId, setOfficerId] = useState(officers[0]?.id || '')
  const [successful, setSuccessful] = useState(true)
  const [duration, setDuration] = useState('')
  const [notes, setNotes] = useState('')
  const [error, setError] = useState(null)
  const [submitting, setSubmitting] = useState(false)

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError(null)
    setSubmitting(true)
    try {
      const res = await fetch(`${API_BASE}/calls`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: token },
        body: JSON.stringify({ account_id: account.account_id, officer_id: officerId, successful, duration_seconds: successful ? parseInt(duration, 10) : null, notes }),
      })
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || 'Failed to log call')
      onSuccess()
    } catch (err) {
      setError(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="modal-overlay" onClick={onClose}>
      <form className="modal-form" onClick={(e) => e.stopPropagation()} onSubmit={handleSubmit}>
        <h3>Log Call</h3>
        <label>Officer</label>
        <select value={officerId} onChange={(e) => setOfficerId(e.target.value)} required>
          {officers.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
        </select>
        <label className="checkbox-label">
          <input type="checkbox" checked={successful} onChange={(e) => setSuccessful(e.target.checked)} />
          Call connected
        </label>
        {successful && (
          <>
            <label>Duration (seconds)</label>
            <input type="number" value={duration} onChange={(e) => setDuration(e.target.value)} required min="1" />
          </>
        )}
        <label>Notes</label>
        <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows="3" />
        {error && <p className="login-error">{error}</p>}
        <div className="modal-actions">
          <button type="button" className="secondary-button" onClick={onClose}>Cancel</button>
          <button type="submit" disabled={submitting}>{submitting ? 'Saving...' : 'Save call'}</button>
        </div>
      </form>
    </div>
  )
}

function LegalReferralModal({ account, officers, token, onClose, onSuccess }) {
  const [officerId, setOfficerId] = useState(officers[0]?.id || '')
  const [lawFirms, setLawFirms] = useState([])
  const [lawFirmId, setLawFirmId] = useState('')
  const [escalationType, setEscalationType] = useState('letter_of_demand')
  const [error, setError] = useState(null)
  const [submitting, setSubmitting] = useState(false)

  useEffect(() => {
    fetch(`${API_BASE}/law-firms`, { headers: { Authorization: token } })
      .then((res) => res.json())
      .then((firms) => {
        setLawFirms(firms)
        if (firms.length) setLawFirmId(firms[0].id)
      })
      .catch(() => {})
  }, [token])

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError(null)
    setSubmitting(true)
    try {
      const res = await fetch(`${API_BASE}/legal-referrals`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: token },
        body: JSON.stringify({ account_id: account.account_id, officer_id: officerId, law_firm_id: lawFirmId, escalation_type: escalationType }),
      })
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || 'Failed to push referral')
      onSuccess()
    } catch (err) {
      setError(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="modal-overlay" onClick={onClose}>
      <form className="modal-form" onClick={(e) => e.stopPropagation()} onSubmit={handleSubmit}>
        <h3>Push to Law Firm</h3>
        <label>Referring Officer</label>
        <select value={officerId} onChange={(e) => setOfficerId(e.target.value)} required>
          {officers.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
        </select>
        <label>Law Firm</label>
        <select value={lawFirmId} onChange={(e) => setLawFirmId(e.target.value)} required>
          {lawFirms.map((f) => <option key={f.id} value={f.id}>{f.name}</option>)}
        </select>
        <label>Document Type</label>
        <select value={escalationType} onChange={(e) => setEscalationType(e.target.value)} required>
          <option value="letter_of_demand">Letter of Demand</option>
          <option value="originating_claim">Originating Claim</option>
          <option value="judgment_order">Judgment Order</option>
          <option value="garnishee_order">Garnishee Order</option>
          <option value="writ_of_seizure_and_sale">Writ of Seizure and Sale</option>
          <option value="statutory_demand">Statutory Demand</option>
          <option value="bankruptcy_notice">Bankruptcy Notice</option>
        </select>
        {error && <p className="login-error">{error}</p>}
        <div className="modal-actions">
          <button type="button" className="secondary-button" onClick={onClose}>Cancel</button>
          <button type="submit" disabled={submitting}>{submitting ? 'Pushing...' : 'Push case'}</button>
        </div>
      </form>
    </div>
  )
}

function CustomerDetail({ customerId, officers, token, onBack }) {
  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [callModalAccount, setCallModalAccount] = useState(null)
  const [legalModalAccount, setLegalModalAccount] = useState(null)
  const [toast, setToast] = useState(null)

  const load = () => {
    fetch(`${API_BASE}/customers/${customerId}`, { headers: { Authorization: token } })
      .then((res) => {
        if (!res.ok) throw new Error(`API returned ${res.status}`)
        return res.json()
      })
      .then((d) => { setData(d); setLoading(false) })
      .catch((err) => { setError(err.message); setLoading(false) })
  }

  useEffect(load, [customerId, token])

  const viewDocument = async (escalationId, docType) => {
    try {
      const res = await fetch(`${API_BASE}/documents/url?escalation_id=${escalationId}&doc_type=${docType}`, {
        headers: { Authorization: token },
      })
      const d = await res.json()
      if (!res.ok) throw new Error(d.error || 'Failed to get document link')
      window.open(d.url, '_blank')
    } catch (err) {
      alert(err.message)
    }
  }

  const handleCallLogged = () => {
    setCallModalAccount(null)
    setToast('Call logged successfully')
    load()
    setTimeout(() => setToast(null), 3000)
  }

  const handleReferralPushed = () => {
    setLegalModalAccount(null)
    setToast('Case pushed to law firm')
    load()
    setTimeout(() => setToast(null), 3000)
  }

  if (loading) return <div className="status-message">Loading customer...</div>
  if (error) return <div className="status-message error">Error: {error}</div>

  const { customer, accounts, events } = data

  return (
    <div className="dashboard">
      <button className="back-button" onClick={onBack}>← Back to Dashboard</button>
      {toast && <div className="toast">{toast}</div>}
      <div className="detail-grid">
        <section className="detail-card">
          <h2>{customer.name}</h2>
          <dl>
            <dt>Phone</dt><dd>{customer.phone}</dd>
            <dt>Email</dt><dd>{customer.email}</dd>
            <dt>Address</dt><dd>{customer.address}</dd>
            <dt>Date of Birth</dt><dd>{customer.date_of_birth}</dd>
            <dt>NRIC</dt><dd>{customer.national_id}</dd>
          </dl>
        </section>
        <section className="detail-card">
          <h3>Loan Accounts</h3>
          <table className="mini-table">
            <thead><tr><th>Product</th><th>Loan</th><th>Overdue</th><th>Days</th><th>Stage</th><th></th></tr></thead>
            <tbody>
              {accounts.map((acc) => (
                <tr key={acc.account_id}>
                  <td>{acc.product_type.replace(/_/g, ' ')}</td>
                  <td>${acc.loan_amount.toLocaleString()}</td>
                  <td>${acc.amount_overdue.toLocaleString()}</td>
                  <td>{acc.days_overdue}</td>
                  <td><StageBadge stage={acc.delinquency_stage} /></td>
                  <td>
                    <button className="call-button" onClick={() => setCallModalAccount(acc)}>Log Call</button>
                    <button className="legal-button" onClick={() => setLegalModalAccount(acc)}>Send Legal Letter</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
        <section className="detail-card full-width">
          <h3>Event History</h3>
          {events.length === 0 && <p className="subtitle">No events yet.</p>}
          <div className="event-feed">
            {events.map((ev) => (
              <div className="event-row" key={ev.id}>
                <span className="event-icon">{EVENT_ICONS[ev.event_type] || '•'}</span>
                <div className="event-body">
                  <p className="event-summary">{ev.summary}</p>
                  <p className="event-time">{new Date(ev.event_time).toLocaleString()}</p>
                </div>
                {ev.event_type === 'legal_letter' && (
                  <div>
                    <button className="secondary-button" onClick={() => viewDocument(ev.id, 'referral')} style={{ fontSize: '12px', padding: '4px 10px', marginRight: '4px' }}>
                      Referral
                    </button>
                    <button className="secondary-button" onClick={() => viewDocument(ev.id, 'confirmation')} style={{ fontSize: '12px', padding: '4px 10px' }}>
                      Confirmation
                    </button>
                  </div>
                )}
              </div>
            ))}
          </div>
        </section>
      </div>

      {callModalAccount && (
        <LogCallModal account={callModalAccount} officers={officers} token={token} onClose={() => setCallModalAccount(null)} onSuccess={handleCallLogged} />
      )}
      {legalModalAccount && (
        <LegalReferralModal account={legalModalAccount} officers={officers} token={token} onClose={() => setLegalModalAccount(null)} onSuccess={handleReferralPushed} />
      )}
    </div>
  )
}

function Dashboard({ token, onLogout, onSelectCustomer }) {
  const [accounts, setAccounts] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    fetch(`${API_BASE}/accounts`, { headers: { Authorization: token } })
      .then((res) => { if (!res.ok) throw new Error(`API returned ${res.status}`); return res.json() })
      .then((data) => { setAccounts(data); setLoading(false) })
      .catch((err) => { setError(err.message); setLoading(false) })
  }, [token])

  if (loading) return <div className="status-message">Loading accounts...</div>
  if (error) return <div className="status-message error">Error: {error}</div>

  return (
    <div className="dashboard">
      <div className="dashboard-header">
        <div>
          <h1>Collections Dashboard</h1>
          <p className="subtitle">{accounts.length} accounts loaded from live API</p>
        </div>
        <button className="logout-button" onClick={onLogout}>Log out</button>
      </div>
      <table>
        <thead><tr><th>Customer</th><th>Product</th><th>Loan Amount</th><th>Overdue</th><th>Days Overdue</th><th>Stage</th></tr></thead>
        <tbody>
          {accounts.map((acc) => (
            <tr key={acc.account_id}>
              <td><button className="customer-link" onClick={() => onSelectCustomer(acc.customer_id)}>{acc.customer_name}</button></td>
              <td>{acc.product_type.replace(/_/g, ' ')}</td>
              <td>${acc.loan_amount.toLocaleString()}</td>
              <td>${acc.amount_overdue.toLocaleString()}</td>
              <td>{acc.days_overdue}</td>
              <td><StageBadge stage={acc.delinquency_stage} /></td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function FirmCaseDetail({ escalationId, token, onBack, onMarked }) {
  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [submitting, setSubmitting] = useState(false)
  const [file, setFile] = useState(null)

  const load = () => {
    fetch(`${API_BASE}/firm/referrals/${escalationId}`, { headers: { Authorization: token } })
      .then((res) => { if (!res.ok) throw new Error(`API returned ${res.status}`); return res.json() })
      .then((d) => { setData(d); setLoading(false) })
      .catch((err) => { setError(err.message); setLoading(false) })
  }

  useEffect(load, [escalationId, token])

  const fileToBase64 = (f) => new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(reader.result.split(',')[1])
    reader.onerror = reject
    reader.readAsDataURL(f)
  })

  const handleMarkSent = async () => {
    setSubmitting(true)
    try {
      const body = {}
      if (file) {
        body.document_base64 = await fileToBase64(file)
      }
      const res = await fetch(`${API_BASE}/firm/referrals/${escalationId}/mark-sent`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: token },
        body: JSON.stringify(body),
      })
      if (!res.ok) throw new Error('Failed to mark as sent')
      onMarked()
    } catch (err) {
      alert(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  const viewDocument = async (docType) => {
    try {
      const res = await fetch(`${API_BASE}/documents/url?escalation_id=${escalationId}&doc_type=${docType}`, {
        headers: { Authorization: token },
      })
      const d = await res.json()
      if (!res.ok) throw new Error(d.error || 'Failed to get document link')
      window.open(d.url, '_blank')
    } catch (err) {
      alert(err.message)
    }
  }

  if (loading) return <div className="status-message">Loading case...</div>
  if (error) return <div className="status-message error">Error: {error}</div>

  const { case: c, legal_history } = data

  return (
    <div className="dashboard">
      <button className="back-button" onClick={onBack}>← Back to Queue</button>
      <div className="detail-grid">
        <section className="detail-card">
          <h2>{c.name}</h2>
          <dl>
            <dt>Phone</dt><dd>{c.phone}</dd>
            <dt>Email</dt><dd>{c.email}</dd>
            <dt>Address</dt><dd>{c.address}</dd>
            <dt>NRIC</dt><dd>{c.national_id}</dd>
          </dl>
        </section>
        <section className="detail-card">
          <h3>Case Details</h3>
          <dl>
            <dt>Product</dt><dd>{c.product_type.replace(/_/g, ' ')}</dd>
            <dt>Loan amount</dt><dd>${c.loan_amount.toLocaleString()}</dd>
            <dt>Overdue</dt><dd>${c.amount_overdue.toLocaleString()}</dd>
            <dt>Days overdue</dt><dd>{c.days_overdue}</dd>
            <dt>Status</dt><dd>{c.status}</dd>
          </dl>
          <button className="secondary-button" onClick={() => viewDocument('referral')} style={{ marginTop: '8px', marginRight: '8px' }}>
            View Referral Document
          </button>
          {c.status === 'sent' && (
            <button className="secondary-button" onClick={() => viewDocument('confirmation')} style={{ marginTop: '8px' }}>
              View Confirmation Document
            </button>
          )}
          {c.status === 'drafted' && (
            <div style={{ marginTop: '16px' }}>
              <label style={{ display: 'block', fontSize: '13px', color: '#9a9a9a', marginBottom: '6px' }}>
                Upload confirmation document (optional)
              </label>
              <input type="file" accept="application/pdf" onChange={(e) => setFile(e.target.files[0])} style={{ marginBottom: '10px', fontSize: '13px' }} />
              <br />
              <button className="call-button" onClick={handleMarkSent} disabled={submitting}>
                {submitting ? 'Saving...' : `Mark ${c.escalation_type.replace(/_/g, ' ')} as Sent`}
              </button>
            </div>
          )}
        </section>
        <section className="detail-card full-width">
          <h3>Legal History (this account)</h3>
          <div className="event-feed">
            {legal_history.map((h) => (
              <div className="event-row" key={h.id}>
                <span className="event-icon">⚖️</span>
                <div className="event-body">
                  <p className="event-summary">{h.escalation_type.replace(/_/g, ' ')} - {h.status}</p>
                  <p className="event-time">{new Date(h.created_at).toLocaleString()}</p>
                </div>
              </div>
            ))}
          </div>
        </section>
      </div>
    </div>
  )
}

function LawFirmPortal({ token, onLogout }) {
  const [referrals, setReferrals] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [selectedId, setSelectedId] = useState(null)

  const load = () => {
    fetch(`${API_BASE}/firm/referrals`, { headers: { Authorization: token } })
      .then((res) => { if (!res.ok) throw new Error(`API returned ${res.status}`); return res.json() })
      .then((data) => { setReferrals(data); setLoading(false) })
      .catch((err) => { setError(err.message); setLoading(false) })
  }

  useEffect(load, [token])

  if (selectedId) {
    return (
      <FirmCaseDetail
        escalationId={selectedId}
        token={token}
        onBack={() => setSelectedId(null)}
        onMarked={() => { setSelectedId(null); load() }}
      />
    )
  }

  if (loading) return <div className="status-message">Loading referrals...</div>
  if (error) return <div className="status-message error">Error: {error}</div>

  return (
    <div className="dashboard">
      <div className="dashboard-header">
        <div>
          <h1>Law Firm Portal</h1>
          <p className="subtitle">{referrals.length} cases referred to you</p>
        </div>
        <button className="logout-button" onClick={onLogout}>Log out</button>
      </div>
      <table>
        <thead><tr><th>Customer</th><th>Product</th><th>Overdue</th><th>Status</th><th>Referred</th></tr></thead>
        <tbody>
          {referrals.map((r) => (
            <tr key={r.id}>
              <td><button className="customer-link" onClick={() => setSelectedId(r.id)}>{r.customer_name}</button></td>
              <td>{r.product_type.replace(/_/g, ' ')}</td>
              <td>${r.amount_overdue.toLocaleString()}</td>
              <td>{r.status}</td>
              <td>{new Date(r.created_at).toLocaleDateString()}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function App() {
  const [token, setToken] = useState(null)
  const [claims, setClaims] = useState({})
  const [selectedCustomerId, setSelectedCustomerId] = useState(null)
  const [officers, setOfficers] = useState([])

  const handleLogin = (idToken) => {
    setToken(idToken)
    setClaims(decodeToken(idToken))
  }

  useEffect(() => {
    if (!token || claims['custom:role'] !== 'officer') return
    fetch(`${API_BASE}/officers`, { headers: { Authorization: token } })
      .then((res) => res.json())
      .then(setOfficers)
      .catch(() => {})
  }, [token, claims])

  if (!token) return <LoginForm onLogin={handleLogin} />

  if (claims['custom:role'] === 'law_firm') {
    return <LawFirmPortal token={token} onLogout={() => setToken(null)} />
  }

  if (selectedCustomerId) {
    return (
      <CustomerDetail
        customerId={selectedCustomerId}
        officers={officers}
        token={token}
        onBack={() => setSelectedCustomerId(null)}
      />
    )
  }

  return (
    <Dashboard token={token} onLogout={() => setToken(null)} onSelectCustomer={setSelectedCustomerId} />
  )
}

export default App