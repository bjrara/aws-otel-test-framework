package com.amazon.aoc.validators;

import com.amazon.aoc.helpers.MustacheHelper;
import com.amazon.aoc.models.Context;
import com.amazon.aoc.models.JsonSchemaFileConfig;
import com.amazonaws.services.logs.model.FilteredLogEvent;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.extern.log4j.Log4j2;
import org.apache.commons.io.FilenameUtils;

import java.time.Instant;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;


@Log4j2
public class ContainerInsightStructuredLogValidator
        extends AbstractStructuredLogValidator {

  private static final List<String> LOG_TYPE_TO_VALIDATE = Arrays.asList(
          "Cluster",
          "ClusterNamespace",
          "ClusterService",
          "Container",
          "ContainerFS",
          "Node",
          "NodeDiskIO",
          "NodeFS",
          "NodeNet",
          "Pod",
          "PodNet"
  );

  private static final int MAX_RETRY_COUNT = 15;
  private static final int QUERY_LIMIT = 100;

  @Override
  void init(Context context, String templatePath) throws Exception {
    logGroupName = String.format("/aws/containerinsights/%s/performance",
            context.getCloudWatchContext().getClusterName());
    MustacheHelper mustacheHelper = new MustacheHelper();
    for (String logType : LOG_TYPE_TO_VALIDATE) {
      String templateInput = mustacheHelper.render(new JsonSchemaFileConfig(
              FilenameUtils.concat(templatePath, logType + ".json")), context);
      schemasToValidate.put(logType, parseJsonSchema(templateInput));
    }
  }

  @Override
  String getJsonSchemaMappingKey(JsonNode jsonNode) {
    return jsonNode.get("Type").asText();
  }

  @Override
  protected int getMaxRetryCount() {
    return MAX_RETRY_COUNT;
  }

  @Override
  protected void fetchAndValidateLogs(Instant startTime) throws Exception {
    Set<String> logTypes = new HashSet<>(LOG_TYPE_TO_VALIDATE);
    log.info("Fetch and validate logs with types: " + String.join(", ", logTypes));
    for (String logType : logTypes) {
      String filterPattern = String.format("{ $.Type = \"%s\"}", logType);
      List<FilteredLogEvent> logEvents = cloudWatchService.filterLogs(logGroupName, filterPattern,
              startTime.toEpochMilli(), QUERY_LIMIT);
      for (FilteredLogEvent logEvent : logEvents) {
        validateJsonSchema(logEvent.getMessage());
      }
    }
  }

}