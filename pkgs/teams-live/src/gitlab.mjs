export class GitLabClient {
  constructor({ host = 'git.wiit.one', token = null } = {}) {
    this.host = host;
    this.token = token;
    this.baseUrl = `https://${host}/api/v4`;
    const escapedHost = host.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    this.mrUrlRegex = new RegExp(`https?:\\/\\/${escapedHost}\\/([\\w.\\/-]+?)\\/-\\/merge_requests\\/(\\d+)`, 'g');
  }

  async request(path, { method = 'GET', body = null } = {}) {
    const url = `${this.baseUrl}/${path.replace(/^\/+/, '')}`;
    const headers = {
      'User-Agent': 'teams-live/1.0',
    };
    if (this.token) {
      headers['PRIVATE-TOKEN'] = this.token;
    }
    if (body) {
      headers['Content-Type'] = 'application/json';
    }

    const options = {
      method,
      headers,
      signal: AbortSignal.timeout(15_000),
    };
    if (body) {
      options.body = JSON.stringify(body);
    }

    const res = await fetch(url, options);
    if (!res.ok) {
      const errText = await res.text().catch(() => '');
      let msg = errText;
      try {
        const parsed = JSON.parse(errText);
        msg = parsed.message || parsed.error || errText;
      } catch {
        // use raw text
      }
      throw new Error(`GitLab error (${res.status}): ${typeof msg === 'string' ? msg : JSON.stringify(msg)}`);
    }
    return await res.json();
  }

  findMrLinks(text) {
    const results = [];
    if (!text) return results;
    for (const match of text.matchAll(this.mrUrlRegex)) {
      results.push({
        project: match[1],
        iid: match[2],
        url: match[0],
      });
    }
    return results;
  }

  mrLink(project, iid) {
    return `https://${this.host}/${project}/-/merge_requests/${iid}`;
  }

  async getMr(project, iid) {
    return await this.request(`projects/${encodeURIComponent(project)}/merge_requests/${iid}`);
  }

  async approveMr(project, iid, { sha = null } = {}) {
    const body = sha ? { sha } : {};
    return await this.request(
      `projects/${encodeURIComponent(project)}/merge_requests/${iid}/approve`,
      { method: 'POST', body }
    );
  }

  async rebaseMr(project, iid, { skipCi = false } = {}) {
    return await this.request(
      `projects/${encodeURIComponent(project)}/merge_requests/${iid}/rebase`,
      { method: 'PUT', body: { skip_ci: skipCi } }
    );
  }

  async getApprovals(project, iid) {
    return await this.request(`projects/${encodeURIComponent(project)}/merge_requests/${iid}/approvals`);
  }

  async getPipelines(project, iid) {
    return await this.request(`projects/${encodeURIComponent(project)}/merge_requests/${iid}/pipelines?per_page=1`);
  }

  /**
   * Retrieves combined MR status, rebase/conflict status, and latest pipeline state.
   */
  async getMrStatus(project, iid) {
    const mr = await this.getMr(project, iid);
    const state = mr.state; // 'opened' | 'merged' | 'closed'

    let approved = false;
    let status = state;

    if (state !== 'merged' && state !== 'closed') {
      try {
        const approvals = await this.getApprovals(project, iid);
        approved = !!approvals.approved;
        status = approved ? 'approved' : 'pending';
      } catch {
        status = 'pending';
      }
    }

    const detailedMergeStatus = mr.detailed_merge_status || mr.merge_status;
    const hasConflicts = mr.has_conflicts === true || detailedMergeStatus === 'conflict';
    const needsRebase =
      state === 'opened' &&
      (detailedMergeStatus === 'need_rebase' || hasConflicts || mr.should_be_rebased === true);

    let latestPipeline = null;
    try {
      const pipelines = await this.getPipelines(project, iid);
      if (Array.isArray(pipelines) && pipelines.length > 0) {
        latestPipeline = {
          id: pipelines[0].id,
          status: pipelines[0].status,
          web_url: pipelines[0].web_url,
          ref: pipelines[0].ref,
          sha: pipelines[0].sha,
        };
      }
    } catch {
      // Pipelines retrieval optional
    }

    return {
      project,
      iid,
      title: mr.title,
      web_url: mr.web_url,
      state,
      approved,
      status, // 'pending' | 'approved' | 'merged' | 'closed'
      detailedMergeStatus,
      hasConflicts,
      needsRebase,
      pipeline: latestPipeline,
    };
  }
}
