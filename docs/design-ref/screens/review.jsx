// studio/screens/review.jsx — post-capture review: coverage map, weak spots, retake (iPhone · iPad)

const REVIEW_STATS = [
  { k: 'Frames', v: '340' },
  { k: 'Coverage', v: '92%', c: () => T.good },
  { k: 'Sharpness', v: '0.93' },
  { k: 'Parallax', v: '8.4°' },
  { k: 'Rejected', v: '6', c: () => T.warn },
];

function sevColor(s) { return s === 'high' ? T.bad : s === 'med' ? T.warn : T.accent; }

// ─── iPhone ─────────────────────────────────────────────────────────
function PhoneReview({ go }) {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg }}>
      <StatusBar />
      <div className="st-scroll" style={{ position: 'absolute', inset: 0, top: 54, overflow: 'auto', padding: '8px 20px 110px' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <button className="st-tap" onClick={() => go('viewfinder')} style={{ width: 36, height: 36, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="back" s={17} c={T.text2} /></button>
          <Chip tone="good"><span style={{ width: 6, height: 6, borderRadius: 99, background: T.good }} /> Capture complete</Chip>
          <button className="st-tap" style={{ width: 36, height: 36, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="share" s={16} c={T.text2} /></button>
        </div>
        <div style={{ marginTop: 18 }}>
          <Label color={T.good}>Coverage 92% · 340 frames</Label>
          <div style={{ fontSize: 28, fontWeight: 720, letterSpacing: -0.9, color: T.ink, marginTop: 6 }}>Review &amp; retake</div>
          <div style={{ fontSize: 13.5, color: T.text2, marginTop: 8 }}>3 weak spots flagged. Retake them, or proceed to compute.</div>
        </div>
        <Card radius={22} style={{ padding: 16, marginTop: 14, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
          <div style={{ display: 'flex', gap: 18, alignSelf: 'stretch', justifyContent: 'center', marginBottom: 4 }}>
            {[['Strong', T.good], ['Weak', T.warn], ['Missing', T.bad]].map(([l, c]) => (
              <div key={l} style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <span style={{ width: 8, height: 8, borderRadius: 99, background: c }} />
                <Label>{l}</Label>
              </div>
            ))}
          </div>
          <CoverageDome size={258} drops={DROPS} />
        </Card>
        <Card radius={20} style={{ padding: '4px 16px', marginTop: 12 }}>
          {DROPS.map((d, i) => {
            const c = sevColor(d.severity);
            return (
              <React.Fragment key={d.id}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '11px 0' }}>
                  <span style={{ width: 22, height: 22, borderRadius: 99, background: `${c}1f`, display: 'grid', placeItems: 'center', flexShrink: 0 }}>
                    <span className="st-num" style={{ fontSize: 11, fontWeight: 700, color: c }}>{i + 1}</span>
                  </span>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: 13.5, fontWeight: 650, color: T.ink }}>{d.label}</div>
                    <div className="st-num" style={{ fontSize: 11, color: T.text3, marginTop: 1 }}>{d.hint}</div>
                  </div>
                  <button className="st-tap" onClick={() => go('viewfinder')} style={{ height: 30, padding: '0 12px', borderRadius: 99, border: 'none', cursor: 'pointer', background: T.fieldFillHi, fontSize: 12.5, fontWeight: 600, color: T.ink }}>Retake</button>
                </div>
                {i < DROPS.length - 1 && <Rule />}
              </React.Fragment>
            );
          })}
        </Card>
      </div>
      <div style={{ position: 'absolute', bottom: 28, left: 20, right: 20, display: 'flex', gap: 8 }}>
        <Button kind="secondary" style={{ flex: 1 }} onClick={() => go('viewfinder')}><Ic name="refresh" s={15} c={T.ink} /> Retake all</Button>
        <Button kind="accent" style={{ flex: 1.5 }} onClick={() => go('compute')}><Ic name="chip" s={16} c={T.onAccent} /> Compute now</Button>
      </div>
    </div>
  );
}

// ─── iPad ───────────────────────────────────────────────────────────
function PadReview({ go }) {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg }}>
      <PadStatusBar />
      <div style={{ position: 'absolute', inset: 0, top: 30, display: 'flex', flexDirection: 'column', padding: 24 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <button className="st-tap" onClick={() => go('viewfinder')} style={{ width: 38, height: 38, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="back" s={17} c={T.text2} /></button>
            <div><Label color={T.good}>Post-capture · Object</Label><div style={{ fontSize: 17, fontWeight: 700, letterSpacing: -0.3, color: T.ink, marginTop: 2 }}>Review &amp; retake</div></div>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <Button kind="secondary" size="sm" onClick={() => go('viewfinder')}><Ic name="refresh" s={15} c={T.ink} /> Retake all</Button>
            <Button kind="accent" size="sm" onClick={() => go('compute')}><Ic name="chip" s={16} c={T.onAccent} /> Compute now</Button>
          </div>
        </div>
        <div style={{ flex: 1, display: 'grid', gridTemplateColumns: '1.1fr .9fr', gap: 16, minHeight: 0, marginTop: 18 }}>
          {/* coverage hero */}
          <Card radius={24} style={{ padding: 24, display: 'flex', flexDirection: 'column', minHeight: 0 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
              <div>
                <Label color={T.good}>Coverage map · 92%</Label>
                <div style={{ fontSize: 34, fontWeight: 720, letterSpacing: -1.1, color: T.ink, marginTop: 6, lineHeight: 1.02 }}>You almost have it.</div>
                <div style={{ fontSize: 14, color: T.text2, marginTop: 6, lineHeight: 1.4, maxWidth: 360 }}>Three weak spots — color-coded shells show density and angle confidence around the object.</div>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {[['Strong', T.good], ['Weak', T.warn], ['Missing', T.bad]].map(([l, c]) => (
                  <div key={l} style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
                    <span style={{ width: 9, height: 9, borderRadius: 99, background: c }} />
                    <Label>{l}</Label>
                  </div>
                ))}
              </div>
            </div>
            <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: 0 }}>
              <CoverageDome size={400} drops={DROPS} />
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: 12, paddingTop: 14, borderTop: `0.5px solid ${T.line}` }}>
              {REVIEW_STATS.map(s => <Stat key={s.k} k={s.k} v={s.v} c={s.c ? s.c() : undefined} size="sm" />)}
            </div>
          </Card>
          {/* weak spots + frame strip */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 14, minHeight: 0 }}>
            <Card radius={20} style={{ padding: 18 }}>
              <Label color={T.warn}>Weak spots — 3 flagged</Label>
              <div style={{ marginTop: 10 }}>
                {DROPS.map((d, i) => {
                  const c = sevColor(d.severity);
                  return (
                    <div key={d.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 0', borderTop: i ? `0.5px solid ${T.line}` : 'none' }}>
                      <div style={{ width: 30, height: 30, borderRadius: 99, display: 'grid', placeItems: 'center', background: `${c}1f` }}>
                        <span className="st-num" style={{ fontSize: 13, fontWeight: 700, color: c }}>{i + 1}</span>
                      </div>
                      <div style={{ flex: 1 }}>
                        <div style={{ fontSize: 14, fontWeight: 650, color: T.ink }}>{d.label}</div>
                        <div className="st-num" style={{ fontSize: 11.5, color: T.text3 }}>{d.hint}</div>
                      </div>
                      <div style={{ display: 'flex', gap: 6 }}>
                        <Button kind="ghost" size="sm">Skip</Button>
                        <Button kind="secondary" size="sm" onClick={() => go('viewfinder')}>Retake</Button>
                      </div>
                    </div>
                  );
                })}
              </div>
            </Card>
            <Card radius={20} style={{ padding: 18, flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Label color={T.accentText}>Frame timeline · 340</Label>
                <Segmented size="sm" options={['All', 'Keep', 'Reject']} value="All" onChange={() => {}} />
              </div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4, marginTop: 14, alignContent: 'flex-start' }}>
                {[...Array(72)].map((_, i) => {
                  const rej = i === 14 || i === 32 || i === 33 || i === 51 || i === 60;
                  const tones = [['#EFE7D7', '#9B8769'], ['#D8C3A4', '#7A6244'], ['#CBB592', '#5E4B30']];
                  const [a, b] = tones[i % 3];
                  return (
                    <div key={i} style={{
                      width: 'calc(8.333% - 4px)', aspectRatio: '1', borderRadius: 5, position: 'relative', overflow: 'hidden',
                      background: rej ? T.badSoft : `radial-gradient(circle at 36% 30%, ${a}, ${b})`,
                      border: rej ? `0.5px solid ${T.bad}` : `0.5px solid ${T.line}`, opacity: rej ? 0.8 : 1,
                    }}>
                      {rej && <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', color: T.bad, fontSize: 11, fontWeight: 700 }}>×</div>}
                    </div>
                  );
                })}
              </div>
              <div style={{ display: 'flex', gap: 14, marginTop: 'auto', paddingTop: 14, borderTop: `0.5px solid ${T.line}` }}>
                <div style={{ flex: 1 }}><Stat k="Kept" v="334" c={T.good} size="sm" /></div>
                <div style={{ flex: 1 }}><Stat k="Rejected" v="6" c={T.warn} size="sm" /></div>
                <div style={{ flex: 1 }}><Stat k="Interval" v="0.18s" size="sm" /></div>
              </div>
            </Card>
          </div>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { PhoneReview, PadReview });
