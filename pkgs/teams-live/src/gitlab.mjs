export class GitLabClient {
  constructor({ host = 'git.wiit.one', token = null, group = '' } = {}) {
    this.host = (host || 'git.wiit.one').replace(/^https?:\/\//, '').replace(/\/+$/, '');
    this.token = token;
    this.group = group;
    this.baseUrl = `https://${this.host}/api/v4`;
    const escapedHost = this.host.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
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

    let res;
    try {
      res = await fetch(url, options);
    } catch (err) {
      try {
        res = await fetch(url, options);
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

  findMrLinks(text) {
    const results = [];
    if (!text) return results;
    // Strip quote blocks and reply elements so we don't extract MRs that were merely quoted in a reply
    const textWithoutQuotes = text
      .replace(/<blockquote[\s\S]*?<\/blockquote>/gi, '')
      .replace(/<div[^>]*itemtype="http:\/\/schema\.skype\.com\/Reply"[\s\S]*?<\/div>/gi, '');
    for (const match of textWithoutQuotes.matchAll(this.mrUrlRegex)) {
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
