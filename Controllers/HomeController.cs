using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using basicmvc.Models;

namespace basicmvc.Controllers;

public class HomeController : Controller
{
    private readonly ILogger<HomeController> _logger;

    public HomeController(ILogger<HomeController> logger)
    {
        _logger = logger;
    }

    public IActionResult Index()
    {
        return View();
    }

     public IActionResult BlobStorage()
    {
        string imageUrl = "https://demojjsajk22.blob.core.windows.net/image/hero.jpeg";
        return View(model: imageUrl);
    }

    public IActionResult Privacy()
    {
        return View();
    }

    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public IActionResult Error()
    {
        return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
    }
}
