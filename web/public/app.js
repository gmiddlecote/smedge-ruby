/*
 * Smedge web UI behaviour (no dependencies).
 *  1. Sale form: add/remove item rows and live line totals.
 *  2. Dashboard chart: hover tooltip for the monthly income/expense points.
 */
(function () {
  "use strict";

  // --- Sale form: dynamic item rows --------------------------------------

  var table = document.getElementById("items-table");
  if (!table) { return; }

  var tbody = table.querySelector("tbody");
  var addButton = document.getElementById("add-item");

  function rowTemplate(row) {
    return row.cloneNode(true);
  }

  function clearRow(row) {
    Array.prototype.forEach.call(row.querySelectorAll("input"), function (input) {
      input.value = "";
    });
    row.querySelector(".line-total").textContent = "-";
  }

  function updateTotal(row) {
    var qty = parseFloat(row.querySelector(".qty").value);
    var rate = parseFloat(row.querySelector(".rate").value);
    var cell = row.querySelector(".line-total");
    if (isNaN(qty) || isNaN(rate)) {
      cell.textContent = "-";
      return;
    }
    var total = (qty * rate);
    cell.textContent = "₹" + formatNumber(total);

    if (row.querySelector("input[required]")) {
      row.setAttribute("data-line-total", total);
    }
  }

  function formatNumber(value) {
    return value.toLocaleString("en-IN", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    });
  }

  addButton.addEventListener("click", function () {
    var source = tbody.querySelector("tr");
    var row = rowTemplate(source);
    clearRow(row);
    tbody.appendChild(row);
  });

  tbody.addEventListener("input", function (event) {
    if (event.target.closest(".qty, .rate")) {
      updateTotal(event.target.closest("tr"));
    }
  });

  tbody.addEventListener("click", function (event) {
    if (event.target.classList.contains("remove-row")) {
      if (tbody.querySelectorAll("tr").length > 1) {
        event.target.closest("tr").remove();
      } else {
        clearRow(event.target.closest("tr"));
      }
    }
  });

  Array.prototype.forEach.call(tbody.querySelectorAll("tr"), updateTotal);
})();

(function () {
  "use strict";

  // --- Dashboard chart: hover tooltip ---------------------------------------

  var chart = document.getElementById("monthly-chart");
  if (!chart) { return; }

  var tip = document.createElement("div");
  tip.className = "chart-tip";
  tip.style.display = "none";
  document.body.appendChild(tip);

  function position(e, circle) {
    var point = chart.createSVGPoint();
    point.x = parseFloat(circle.getAttribute("cx"));
    point.y = parseFloat(circle.getAttribute("cy"));
    var screen = point.matrixTransform(chart.getScreenCTM());
    tip.style.left = Math.round(screen.x - 40) + "px";
    tip.style.top = Math.round(screen.y + 12) + "px";
  }

  function show(e, circle) {
    tip.innerHTML =
      '<div class="chart-tip-month">' + circle.getAttribute("data-month") + "</div>" +
      '<div class="chart-tip-row positive">Income ' + circle.getAttribute("data-income") + "</div>" +
      '<div class="chart-tip-row negative">Expense ' + circle.getAttribute("data-expense") + "</div>";
    tip.style.display = "block";
    position(e, circle);
  }

  function hide() {
    tip.style.display = "none";
  }

  Array.prototype.forEach.call(chart.querySelectorAll("circle.dot"), function (circle) {
    circle.addEventListener("mouseover", function (e) { show(e, circle); });
    circle.addEventListener("mousemove", function (e) { position(e, circle); });
    circle.addEventListener("mouseout", hide);
  });
})();