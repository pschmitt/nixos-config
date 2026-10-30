export class GitLabClient {
  constructor({ host = 'git.wiit.one', token = null, group = '' } = {}) {
    this.host = (host || 'git.wiit.one').replace(/^https?:\/\//, '').replace(/\/+$/, '');
    this.token = token;
    this.group = group;
    this.baseUrl = `https://${this.host}/api/v4`;
    const escapedHost = this.host.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    this.mrUrlRegex = new RegExp(`https?:\\/\\/${escapedHost}\\/([\\w.\\/-]+?)\\/-\\/merge_requests\\/(\\d+)`, 'g');
  }

  async request(path, { method = 'GET', body = null, timeoutMs = 30_000 } = {}) {
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

    const makeFetch = () =>
      fetch(url, {
        method,
        headers,
        body: body ? JSON.stringify(body) : undefined,
        signal: AbortSignal.timeout(timeoutMs),
      });

    let res;
    try {
      res = await makeFetch();
    } catch (err) {
      try {
        await new Promise((r) => setTimeout(r, 1000));
        res = await makeFetch();
      } catch (retryErr) {
        throw new Error(`GitLab request failed (${retryErr.cause?.message || retryErr.message})`);
      }
    }
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

  findMrLinks(text, { allowQuotes = false } = {}) {
    const results = [];
    if (!text) return results;

    const textToSearch = allowQuotes
      ? text
      : text
          .replace(/<blockquote[\s\S]*?<\/blockquote>/gi, '')
          .replace(/<div[^>]*itemtype="http:\/\/schema\.skype\.com\/Reply"[\s\S]*?<\/div>/gi, '');

    const seen = new Set();

    // 1. Full URLs (e.g. https://git.wiit.one/kubernetes/workload-clusters/-/merge_requests/596)
    for (const match of textToSearch.matchAll(this.mrUrlRegex)) {
      const project = match[1];
      const iid = match[2];
      const key = `${project}!${iid}`.toLowerCase();
      if (!seen.has(key)) {
        seen.add(key);
        results.push({
          project,
          iid,
          url: match[0],
        });
      }
    }

    // 2. Shorthand references (e.g. workload-clusters!596, kubernetes/workload-clusters!596)
    const shorthandRegex = /(?:^|[^\w/.-])([a-zA-Z0-9_.-]+(?:\/[a-zA-Z0-9_.-]+)*)!(\d+)(?=[^\w]|$)/g;
    for (const match of textToSearch.matchAll(shorthandRegex)) {
      let project = match[1];
      const iid = match[2];
      if (!project.includes('/') && this.group) {
        project = `${this.group}/${project}`;
      }
      const key = `${project}!${iid}`.toLowerCase();
      if (!seen.has(key)) {
        seen.add(key);
        results.push({
          project,
          iid,
          url: this.mrLink(project, iid),
        });
      }
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

  async getGroupMrs(group = null) {
    const targetGroup = group || this.group;
    if (!targetGroup) {
      throw new Error('No GitLab group configured');
    }
    const endpoint = `groups/${encodeURIComponent(targetGroup)}/merge_requests?state=opened&wip=no&per_page=50&order_by=updated_at&sort=desc`;
    const mrs = await this.request(endpoint);
    if (!Array.isArray(mrs)) return [];
    return mrs.filter(
      (m) => !m.draft && !m.work_in_progress && !m.title.startsWith('Draft:') && !m.title.startsWith('WIP:')
    );
  }

  async getPipelines(project, iid) {
    return await this.request(`projects/${encodeURIComponent(project)}/merge_requests/${iid}/pipelines?per_page=1`);
  }

  async getLatestPipeline(project, iid) {
    const pipelines = await this.getPipelines(project, iid);
    if (Array.isArray(pipelines) && pipelines.length > 0) {
      return pipelines[0];
    }
    return null;
  }

  async getPipelineJobs(project, pipelineId) {
    return await this.request(`projects/${encodeURIComponent(project)}/pipelines/${pipelineId}/jobs?per_page=100`);
  }

  async retryPipeline(project, pipelineId) {
    return await this.request(
      `projects/${encodeURIComponent(project)}/pipelines/${pipelineId}/retry`,
      { method: 'POST' }
    );
  }

  /**
   * Retrieves combined MR status, rebase/conflict status, and latest pipeline state.
   */
  async getMrStatus(project, iid) {
    const mr = await this.getMr(project, iid);
    const state = mr.state; // 'opened' | 'merged' | 'closed'

    let approved = false;
    let approvedBy = [];
    let status = state;

    if (state !== 'merged' && state !== 'closed') {
      try {
        const approvals = await this.getApprovals(project, iid);
        approved = !!approvals.approved;
        if (Array.isArray(approvals.approved_by)) {
          approvedBy = approvals.approved_by
            .map((a) => a.user?.name || a.user?.username)
            .filter(Boolean);
        }
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
      target_branch: mr.target_branch,
      state,
      approved,
      approvedBy,
      status, // 'pending' | 'approved' | 'merged' | 'closed'
      detailedMergeStatus,
      hasConflicts,
      needsRebase,
      pipeline: latestPipeline,
    };
  }
}
