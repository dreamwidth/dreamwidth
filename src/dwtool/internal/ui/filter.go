package ui

import (
	"strings"

	"dreamwidth.org/dwtool/internal/model"
)

// filterServices returns only the services whose names contain the filter string (case-insensitive).
func filterServices(services []model.Service, filter string) []model.Service {
	if filter == "" {
		return services
	}
	needle := strings.ToLower(filter)
	var result []model.Service
	for _, svc := range services {
		if strings.Contains(strings.ToLower(svc.Name), needle) {
			result = append(result, svc)
		}
	}
	return result
}
