package com.amazon.aoc.validators;

import com.amazon.aoc.helpers.MustacheHelper;
import com.amazon.aoc.models.CloudWatchContext;
import com.amazon.aoc.models.Context;
import com.amazon.aoc.models.JsonSchemaFileConfig;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.extern.log4j.Log4j2;
import org.apache.commons.io.FilenameUtils;

import java.util.ArrayList;
import java.util.List;

@Log4j2
public class ContainerInsightPrometheusStructuredLogValidator
        extends AbstractStructuredLogValidator {

  private List<CloudWatchContext.App> validateApps;

  @Override
  void init(Context context, String templatePath) throws Exception {
    logGroupName = String.format("/aws/containerinsights/%s/prometheus",
            context.getCloudWatchContext().getClusterName());
    validateApps = getAppsToValidate(context.getCloudWatchContext());
    MustacheHelper mustacheHelper = new MustacheHelper();

    for (CloudWatchContext.App app : validateApps) {
      String templateInput = mustacheHelper.render(new JsonSchemaFileConfig(
              FilenameUtils.concat(templatePath, app.getName() + ".json")), context);
      schemasToValidate.put(app.getNamespace(), parseJsonSchema(templateInput));
      logStreamNames.add(app.getJob());
    }
  }

  @Override
  String getJsonSchemaMappingKey(JsonNode logEventNode) {
    return logEventNode.get("Namespace").asText();
  }

  private static List<CloudWatchContext.App> getAppsToValidate(CloudWatchContext cwContext) {
    List<CloudWatchContext.App> apps = new ArrayList<>();
    if (cwContext.getAppMesh() != null) {
      apps.add(cwContext.getAppMesh());
    }
    if (cwContext.getNginx() != null) {
      apps.add(cwContext.getNginx());
    }
    if (cwContext.getHaproxy() != null) {
      apps.add(cwContext.getHaproxy());
    }
    if (cwContext.getJmx() != null) {
      apps.add(cwContext.getJmx());
    }
    if (cwContext.getMemcached() != null) {
      apps.add(cwContext.getMemcached());
    }
    return apps;
  }

}