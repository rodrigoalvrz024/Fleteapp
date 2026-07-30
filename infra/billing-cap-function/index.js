const {CloudBillingClient} = require('@google-cloud/billing');

const billing = new CloudBillingClient();

function parseBudgetMessage(event) {
  let data = event && event.data;

  if (data && data.message && data.message.data) {
    data = data.message.data;
  } else if (data && data.data) {
    data = data.data;
  }

  if (Buffer.isBuffer(data)) {
    data = data.toString('utf8');
  }

  if (typeof data === 'string') {
    const candidates = [data];
    let decoded = data;

    for (let attempts = 0; attempts < 2; attempts += 1) {
      try {
        decoded = Buffer.from(decoded, 'base64').toString('utf8');
        candidates.push(decoded);
      } catch (error) {
        break;
      }
    }

    for (const candidate of candidates) {
      try {
        return JSON.parse(candidate);
      } catch (error) {
        // Keep trying the next representation of the same Pub/Sub payload.
      }
    }

    const previews = candidates.map(candidate => String(candidate).slice(0, 120));
    throw new Error(`Budget notification data was not valid JSON after direct/base64 decoding. Previews: ${JSON.stringify(previews)}`);
  }

  if (data && typeof data === 'object') {
    return data;
  }

  throw new Error('Budget notification did not include readable Pub/Sub data.');
}

async function isBillingEnabled(projectName) {
  try {
    const [response] = await billing.getProjectBillingInfo({name: projectName});
    return Boolean(response.billingEnabled);
  } catch (error) {
    console.error('Could not read project billing info. Assuming billing is enabled.', error);
    return true;
  }
}

async function disableBilling(projectName) {
  const [response] = await billing.updateProjectBillingInfo({
    name: projectName,
    resource: {billingAccountName: ''},
  });

  return response;
}

exports.stopBilling = async event => {
  const projectId = process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT;
  if (!projectId) {
    throw new Error('GOOGLE_CLOUD_PROJECT is required.');
  }

  const message = parseBudgetMessage(event);
  const costAmount = Number(message.costAmount);
  const budgetAmount = Number(message.budgetAmount);
  const currencyCode = message.currencyCode || 'unknown';
  const projectName = `projects/${projectId}`;

  console.log(
    JSON.stringify({
      message: 'Budget notification received.',
      budgetDisplayName: message.budgetDisplayName,
      costAmount,
      budgetAmount,
      currencyCode,
    })
  );

  if (!Number.isFinite(costAmount) || !Number.isFinite(budgetAmount)) {
    console.warn('Budget notification ignored because costAmount or budgetAmount is not numeric.');
    return;
  }

  if (costAmount < budgetAmount) {
    console.log(`No action. Current cost ${costAmount} ${currencyCode} is below budget ${budgetAmount} ${currencyCode}.`);
    return;
  }

  if (!(await isBillingEnabled(projectName))) {
    console.log('Billing is already disabled.');
    return;
  }

  const response = await disableBilling(projectName);
  console.error(
    JSON.stringify({
      message: 'Billing disabled because budget cap was reached.',
      projectName,
      costAmount,
      budgetAmount,
      currencyCode,
      response,
    })
  );
};
